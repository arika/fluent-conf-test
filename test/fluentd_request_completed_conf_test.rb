# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestCompletedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf 'conf.d/request_completed.conf'

  setup do
    @record = {
      'request_id' => timestamp,
      'severity' => 'INFO',
    }
    @time = Time.now

    @message_base = 'Completed 200 OK in 17ms'
    @status_output = lambda do
      [
        @time,
        'finish.statuses',
        @record.merge(
          'http_status' => '200',
          'duration' => 17
        ),
      ]
    end
  end

  test 'Completed line without extra durations' do
    @record['messages'] = @message_base
    post(record: @record, time: @time)

    assert_equal(
      [
        @status_output.call,
      ],
      results
    )
    assert_empty errors
  end

  test 'Completed line with Views duration' do
    @record['messages'] = 'Completed 200 OK in 17ms (Views: 11.9ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        @status_output.call,
        [
          @time,
          'finish.durations',
          @record.merge(
            'category' => 'Views',
            'duration' => 11.9
          ),
        ],
      ],
      sorted_results
    )
    assert_empty errors
  end

  test 'Completed line with ActiveRecord duration' do
    @record['messages'] = 'Completed 200 OK in 17ms (ActiveRecord: 11.9ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        @status_output.call,
        [
          @time,
          'finish.durations',
          @record.merge(
            'category' => 'ActiveRecord',
            'duration' => 11.9
          ),
        ],
      ],
      sorted_results
    )
    assert_empty errors
  end

  test 'Completed line with some extra durations' do
    @record['messages'] = 'Completed 200 OK in 17ms (Views: 12.3ms | ActiveRecord: 45.6ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        @status_output.call,
        [
          @time,
          'finish.durations',
          @record.merge(
            'category' => 'ActiveRecord',
            'duration' => 45.6
          ),
        ],
        [
          @time,
          'finish.durations',
          @record.merge(
            'category' => 'Views',
            'duration' => 12.3
          ),
        ],
      ],
      sorted_results
    )
    assert_empty errors
  end

  def sorted_results
    results.sort_by { |_, _, record| record['category'] || '' }
  end
end
