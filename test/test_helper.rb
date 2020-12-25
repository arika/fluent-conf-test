# frozen_string_literal: true

require 'test/unit'
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
      }.merge(options)
      @monitor_url = "http://#{@options[:bind_address]}:#{@options[:monitor_port]}/api/plugins.json"
      @error = nil
    end

    def start
      return self if @pid

      @tmpdir = Dir.mktmpdir
      Dir.mkdir(output_dir)
      Dir.mkdir(error_output_dir)

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
      20.times do
        queued_size = metric('_test_output')['buffer_total_queued_size']
        return if queued_size.zero?

        sleep 0.3
      end

      pp metric('_test_output')
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

    def metric(plugin_id)
      metrics['plugins'].detect { |h| h['plugin_id'] == plugin_id }
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
      %W[
        bundle exec fluentd -q
        -c #{__dir__}/fixtures/fluent_record_construction_test.conf
      ]
    end

    def cmdline
      cmdline_base + %w[--no-supervisor]
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
    def fluentd_conf(conf_name)
      @fluentd = Fluentd.new(conf_name)
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

  def results
    flush
    read_output_files(fluentd.output_files)
  end

  def errors
    flush
    read_output_files(fluentd.error_output_files)
  end

  def read_output_files(paths)
    paths.flat_map do |path|
      read_output_file(path)
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
