# frozen_string_literal: true

require 'test/unit'
require 'erb'
require 'fileutils'
require 'fluent-logger'
require 'json'
require 'open-uri'
require 'time'
require 'tmpdir'
require 'uuidtools'

module FluentdConfTestHelper
  class Fluentd
    class Error < RuntimeError; end
    class ConfigError < Error; end
    class FlushError < Error; end

    attr_reader :env, :pid, :error

    def initialize(env)
      @env = env
      @monitor_url = "http://#{env.bind_address}:#{env.monitor_port}/api/plugins.json"
      @error = nil
    end

    def running?
      !@pid.nil?
    end

    def startup
      return if running?

      env.setup
      check_config

      @pid = Process.spawn(*cmdline)
      wait_fluentd
    end

    def shutdown
      return unless running?

      Process.kill(:TERM, @pid)
      Process.waitpid(@pid)
    rescue Errno::ESRCH
      # ignore
    ensure
      @pid = nil
      env.teardown
    end

    def output_files
      env.output_files
    end

    def error_output_files
      env.error_output_files
    end

    def clear_all_outputs
      return unless running?

      flush
      env.clear_all_outputs
    end

    def flush
      return unless running?

      Process.kill(:USR1, @pid)

      limit = Time.now + 5
      s = 0.0
      loop do
        break if Time.now > limit

        s += 0.1
        sleep s
        return if test_outputs_buffer_total_queue_size.zero?
      end

      @error = FlushError.new('flush error')
      raise @error
    end

    def metrics
      JSON.parse(URI.parse(@monitor_url).open(&:read))
    end

    private

    def test_outputs_buffer_total_queue_size
      output_ids_regexp = /\A#{env.label_keys_regexp}\z/
      metrics['plugins']
        .select { |h| output_ids_regexp.match?(h['plugin_id']) }
        .sum { |h| h['buffer_total_queued_size'] }
    end

    def cmdline_base
      %W[fluentd -q -c #{env.test_conf_path}]
    end

    def cmdline
      cmdline_base + %w[--no-supervisor] + %w[-v] * env.verbose_level
    end

    def check_config
      raise @error if @error
      return if system(*cmdline_base, '--dry-run')

      @error = ConfigError.new('config error')
      raise @error
    end

    def wait_fluentd
      limit = Time.now + 10
      loop do
        begin
          metrics
          break
        rescue SystemCallError
          raise if Time.now > limit

          sleep 0.5
        end
      end
    end
  end

  class TestEnv
    TEMPLATE_FILE = File.expand_path('fixtures/fluent_record_construction_test.conf.erb', __dir__)

    attr_reader :conf_path, :forward_port, :monitor_port, :bind_address, :stub_labels, :verbose_level,
                :work_dir, :output_dir, :error_output_dir, :test_conf_path

    def initialize(conf_path:, **options)
      @conf_path = File.expand_path(conf_path, "#{__dir__}/..")
      @forward_port = options[:forward_port] || 24224 # rubocop:disable Style/NumericLiterals
      @monitor_port = options[:monitor_port] || 24220 # rubocop:disable Style/NumericLiterals
      @bind_address = options[:bind_address] || 'localhost'
      @stub_labels = options[:stub_labels] || []
      @verbose_level = options[:verbose_level] || 0
      @work_dir = nil
    end

    def label_key(label)
      format('__label_%s__', label)
    end

    def label_keys_regexp(capture: false)
      r = if capture == true
            ''
          elsif capture
            "?<#{capture}>"
          else
            '?:'
          end
      pattern = "(#{r}#{stub_labels.join('|')})"
      Regexp.new(label_key(pattern))
    end

    def setup
      return if @work_dir

      @work_dir = Dir.mktmpdir
      @output_dir = "#{@work_dir}/app"
      @error_output_dir = "#{@work_dir}/error"
      @test_conf_path = "#{@work_dir}/test_fluent.conf"

      Dir.mkdir(@output_dir)
      Dir.mkdir(@error_output_dir)
      File.write(@test_conf_path, expand_template)
    end

    def teardown
      return unless @work_dir

      work_dir = @work_dir
      @work_dir = @output_dir = @error_output_dir = nil
      FileUtils.remove_entry(work_dir)
    end

    def output_files
      return [] unless @work_dir

      Dir.glob("#{output_dir}/*")
    end

    def error_output_files
      return [] unless @work_dir

      Dir.glob("#{error_output_dir}/*")
    end

    def clear_all_outputs
      (output_files + error_output_files).each do |path|
        FileUtils.remove_entry(path)
      end
    end

    private

    def expand_template
      ERB.new(File.read(TEMPLATE_FILE), trim_mode: '-').result(binding)
    end
  end

  class TestOutput
    module RecordExt
      attr_accessor :label, :time, :tag, :data

      def inspect
        ext = { label: label, time: time, tag: tag }
        super + "(#{ext})"
      end
    end

    def initialize(env)
      @env = env
      @label_keys_regexp = /\A#{env.label_keys_regexp(capture: 'label')}\./
    end

    def outputs(label: nil, time: nil, tag: nil)
      read_output_files.select do |record|
        cond_match?(record.label, label) &&
          cond_match?(record.time, time) &&
          cond_match?(record.tag, tag)
      end
    end

    private

    def cond_match?(value, cond)
      case cond
      when nil
        true
      when Range
        cond.cover?(value)
      when Regexp
        cond.match?(value)
      else
        cond == value
      end
    end

    def read_output_files
      @env.output_files.flat_map do |path|
        read_output_file(path)
      end
    end

    def read_output_file(path)
      records = []
      return records unless File.file?(path)

      File.foreach(path) do |line|
        time, tag, json = line.chomp.split(/\t/, 3)
        m = @label_keys_regexp.match(tag)
        if m
          label = m[:label]
          tag = m.post_match
        end
        records << record(label, time, tag, json)
      end

      records
    end

    def record(label, time, tag, json)
      record = JSON.parse(json)
      record.extend(RecordExt)
      record.label = label
      record.time = Time.parse(time)
      record.tag = tag
      record
    end
  end

  module ClassMethods
    attr_reader :test_output

    def fluentd_conf(**options)
      test_env = TestEnv.new(**options)
      @test_output = TestOutput.new(test_env)
      @fluentd = Fluentd.new(test_env)
    end

    def fluentd
      return @fluentd if @fluentd

      ancestors[1..-1].detect { |klass| klass.respond_to?(:fluentd) }&.fluentd
    end

    def shutdown
      @fluentd&.shutdown
      super
    end
  end

  def self.included(mod)
    mod.module_eval do
      mod.extend ClassMethods

      setup do
        if fluentd.error
          omit "#{fluentd.error.message} found"
        else
          fluentd.startup
        end
      end

      teardown do
        fluentd.clear_all_outputs
      end
    end
  end

  def fluentd
    self.class.fluentd
  end

  def fluent_logger
    return @fluent_logger if @fluent_logger

    @fluent_logger = Fluent::Logger::FluentLogger.new(
      nil,
      host: fluentd.env.bind_address,
      port: fluentd.env.forward_port,
      nanosecond_precision: true
    )
  end

  def post(record:, tag: 'app', time: nil)
    if time
      fluent_logger.post_with_time(tag, record, time)
    else
      fluent_logger.post(tag, record)
    end
  end

  def outputs(**options)
    fluentd.flush
    self.class.test_output.outputs(**options)
  end

  def error_outputs
    fluentd.flush
    fluentd.error_output_files.map { |path| File.read(path) }
  end

  def timestamp
    UUIDTools::UUID.timestamp_create.to_s
  end
end
