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

    attr_reader :pid, :options, :error

    def initialize(conf_name, **options)
      @conf_name = conf_name
      @options = {
        forward_port: ENV['TEST_FORWARD_PORT']&.to_i || 24224, # rubocop:disable Style/NumericLiterals
        monitor_port: ENV['TEST_MONITOR_PORT']&.to_i || 24220, # rubocop:disable Style/NumericLiterals
        bind_address: 'localhost',
        stub_labels: [],
      }.merge(options)
      @monitor_url = "http://#{@options[:bind_address]}:#{@options[:monitor_port]}/api/plugins.json"
      @error = nil
    end

    def start
      return self if @pid

      @tmpdir = Dir.mktmpdir
      Dir.mkdir(output_dir)
      Dir.mkdir(error_output_dir)

      generate_test_conf
      check_config!

      @pid = Process.spawn(env, *cmdline)
      wait_fluentd
      self
    end

    def stop
      return unless @pid

      pid = @pid
      @pid = nil
      Process.kill(:TERM, pid)
      Process.waitpid(pid)
    ensure
      tmpdir = @tmpdir
      @tmpdir = nil
      FileUtils.remove_entry(tmpdir) if tmpdir
    end

    def flush
      return unless @pid

      Process.kill(:USR1, @pid)

      queued_size = nil
      10.times do
        queued_size = test_outputs_buffer_total_queue_size
        return if queued_size.zero?

        sleep 0.5
      end

      @error = Error.new('flush error')
      raise @error
    end

    def clear
      return unless @pid

      flush
      (output_files + error_output_files).each do |path|
        FileUtils.remove_entry(path)
      end
    end

    def metrics
      JSON.parse(URI.parse(@monitor_url).open(&:read))
    end

    def test_outputs_buffer_total_queue_size
      output_ids_regexp = /\A_test_output_(?:#{@options[:stub_labels].join('|')})\z/
      metrics['plugins'].sum do |h|
        output_ids_regexp.match?(h['plugin_id']) ? h['buffer_total_queued_size'] : 0
      end
    end

    def output_dir
      @tmpdir && "#{@tmpdir}/app"
    end

    def error_output_dir
      @tmpdir && "#{@tmpdir}/err"
    end

    def output_files
      Dir.glob("#{output_dir}/*")
    end

    def error_output_files
      Dir.glob("#{error_output_dir}/*")
    end

    private

    def env
      conf_path = File.expand_path(@conf_name, "#{__dir__}/../fluentd")
      {
        'TEST_CONF' => conf_path,
        'TEST_FORWARD_PORT' => @options[:forward_port].to_s,
        'TEST_MONITOR_PORT' => @options[:monitor_port].to_s,
        'TEST_BIND_ADDRESS' => @options[:bind_address],
        'TEST_OUTPUT_DIR' => output_dir,
        'TEST_ERROR_OUTPUT_DIR' => error_output_dir,
      }
    end

    def cmdline_base
      %W[fluentd -q -c #{@test_conf_path}]
    end

    def cmdline
      cmdline_base + %w[--no-supervisor]
    end

    def generate_test_conf
      template_file = File.expand_path('fixtures/fluent_record_construction_test.conf.erb', __dir__)
      template = File.read(template_file)
      options = @options
      test_conf = ERB.new(template, trim_mode: '-').result(binding)

      puts test_conf

      @test_conf_path = "#{@tmpdir}/fluent.conf"
      File.write(@test_conf_path, test_conf)
    end

    def check_config!
      raise @error if @error
      return if system(env, *cmdline_base, '--dry-run')

      @error = ConfigError.new('config error')
      raise @error
    end

    def wait_fluentd
      retry_limit ||= 10
      metrics
    rescue SystemCallError
      retry_limit -= 1
      raise if retry_limit.zero?

      sleep 1
      retry
    end
  end

  module ClassMethods
    def fluentd_conf(*args, **options)
      @fluentd = Fluentd.new(*args, **options)
    end

    def shutdown
      @fluentd&.stop
      super
    end

    def fluentd
      return @fluentd if @fluentd

      ancestors[1..-1].detect { |klass| klass.respond_to?(:fluentd) }&.fluentd
    end
  end

  def self.included(mod)
    mod.module_eval do
      mod.extend ClassMethods

      setup do
        if fluentd.error
          omit "#{fluentd.error.message} found"
        else
          fluentd.start
        end
      end

      teardown do
        fluentd.clear
      end
    end
  end

  def fluentd
    self.class.fluentd
  end

  def fluent_logger
    return @fluent_logger if @fluent_logger

    opts = fluentd.options
    @fluent_logger = Fluent::Logger::FluentLogger.new(
      nil,
      host: opts[:bind_address],
      port: opts[:forward_port],
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

  def flush
    fluentd.flush
  end

  def errors
    flush
    read_output_files(fluentd.error_output_files)
  end

  def outputs(label:, time: nil, tag: nil)
    flush
    outputs = read_output_files(fluentd.output_files)
    filter_outputs(outputs, label: label, time: time, tag: tag)
      .map { |_, _, record| record }
  end

  def read_output_files(paths)
    paths.flat_map do |path|
      read_output_file(path)
    end
  end

  def filter_outputs(outputs, label:, time:, tag:)
    outputs
      .select { |_, out_tag, _| filter_outputs_by_label(out_tag, label) }
      .map { |out_time, out_tag, record| [out_time, out_tag.sub(/\A\.+\./, ''), record] }
      .select do |out_time, out_tag, _|
        filter_outputs_by_time(out_time, time) &&
          filter_outputs_by_tag(out_tag, tag)
      end
  end

  def filter_outputs_by_label(tag, label)
    tag.start_with?("__label_#{label}__.")
  end

  def filter_outputs_by_tag(tag, tag_cond)
    return true unless tag_cond

    if tag_cond.is_a?(Regexp)
      tag_cond.match?(tag)
    else
      tag_cond == tag
    end
  end

  def filter_outputs_by_time(time, time_cond)
    return true unless time_cond

    if time_cond.is_a?(Range)
      time_cond.cover?(time)
    else
      time_cond == time
    end
  end

  def read_output_file(path)
    results = []
    return results unless File.file?(path)

    File.foreach(path) do |line|
      time, tag, json = line.chomp.split(/\t/, 3)
      results << [Time.parse(time), tag, JSON.parse(json)]
    end

    results
  end

  def timestamp
    UUIDTools::UUID.timestamp_create.to_s
  end
end
