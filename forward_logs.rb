# frozen_string_literal: true

require 'time'
require 'uuidtools'
require 'fluent-logger'

fluent_logger = Fluent::Logger::FluentLogger.new(
  nil,
  nanosecond_precision: true
)
fluent_tag = 'app'

log_regexp = /\A., \[(?<time>\S+) #(?<pid>\d+)\]  *(?<severity>\S+) -- :(?: \[(?<request_id>\h{8}-\h{4}-\h{4}-\h{4}-\h{12})\])? (?<message>[^\n]*)/
ansi_escseq_regexp = /\e\[(?:\d{1,2}(?:;\d{1,2})?)?[mK]/
pids = {}
request_ids = {}

ARGF.each_line do |line|
  m = log_regexp.match(line)
  next unless m

  request_id = m[:request_id] || pids[m[:pid]]
  if /\AStarted [A-Z]+ "[^"]*" for /.match?(m[:message])
    unless request_id
      time = Time.parse(m[:time])
      request_id = UUIDTools::UUID.timestamp_create(time).to_s
      pids[m[:pid]] = request_id
    end
    request_ids[request_id] = true
  elsif !request_id || !request_ids.key?(request_id)
    pids.delete(m[:pid])
    next
  elsif /\ACompleted \d+ /.match?(m[:message])
    request_ids.delete(request_id)
    pids.delete(m[:pid])
  end

  data = {
    request_id: request_id,
    severity: m[:severity],
    messages: m[:message].gsub(ansi_escseq_regexp, ''),
  }
  time ||= Time.parse(m[:time])
  puts "#{time.inspect} #{data.inspect}"
  fluent_logger.post_with_time(fluent_tag, data, time)
end
