# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestCompletedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf conf_path: 'fluentd/conf.d/request_completed.conf', stub_labels: %w[OUTPUT]

  setup do
    @record = {
      'request_id' => timestamp,
      'severity' => 'INFO',
    }
    @time = Time.now
    @message_base = 'Completed 200 OK in 17ms'
  end

  test 'Completed line without extra durations' do
    @record['messages'] = @message_base
    post(record: @record, time: @time)

    assert_status_output
    assert_equal 1, outputs.size
    assert_empty error_outputs
  end

  test 'Completed line with Views duration' do
    @record['messages'] = 'Completed 200 OK in 17ms (Views: 11.9ms)'
    post(record: @record, time: @time)

    assert_status_output
    assert_equal(
      [
        @record.merge(
          'category' => 'Views',
          'duration' => 11.9
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.durations')
    )
    assert_equal 2, outputs.size
    assert_empty error_outputs
  end

  test 'Completed line with ActiveRecord duration' do
    @record['messages'] = 'Completed 200 OK in 17ms (ActiveRecord: 11.9ms)'
    post(record: @record, time: @time)

    assert_status_output
    assert_equal(
      [
        @record.merge(
          'category' => 'ActiveRecord',
          'duration' => 11.9
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.durations')
    )
    assert_equal 2, outputs.size
    assert_empty error_outputs
  end

  test 'Completed line with some extra durations' do
    @record['messages'] = 'Completed 200 OK in 17ms (Views: 12.3ms | ActiveRecord: 45.6ms)'
    post(record: @record, time: @time)

    assert_status_output
    assert_equal(
      [
        @record.merge(
          'category' => 'ActiveRecord',
          'duration' => 45.6
        ),
        @record.merge(
          'category' => 'Views',
          'duration' => 12.3
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.durations')
        .sort_by { |h| h['category'] }
    )
    assert_equal 3, outputs.size
    assert_empty error_outputs
  end

  def assert_status_output
    assert_equal(
      [
        @record.merge(
          'http_status' => '200',
          'duration' => 17
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.statuses')
    )
  end
end
