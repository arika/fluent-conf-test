# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestCompletedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf 'conf.d/request_completed.conf'

  setup do
    @request_id = timestamp
    @record = {
      request_id: @request_id,
      severity: 'INFO',
    }
    @time = Time.now

    @message_base = 'Completed 200 OK in 17ms'
    @status_output = [
      @time,
      'finish.statuses',
      {
        'request_id' => @request_id,
        'http_status' => '200',
        'duration' => 17,
      },
    ]
  end

  test 'Completed line without extra durations' do
    @record[:messages] = @message_base
    post(record: @record, time: @time)

    assert_equal(
      [
        @status_output,
      ],
      results
    )
    assert_empty errors
  end

  test 'Completed line with Views duration' do
    @record[:messages] = 'Completed 200 OK in 17ms (Views: 11.9ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        @status_output,
        [
          @time,
          'finish.durations',
          {
            'request_id' => @request_id,
            'category' => 'Views',
            'duration' => 11.9,
          },
        ],
      ],
      sorted_results
    )
    assert_empty errors
  end

  test 'Completed line with ActiveRecord duration' do
    @record[:messages] = 'Completed 200 OK in 17ms (ActiveRecord: 11.9ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        @status_output,
        [
          @time,
          'finish.durations',
          {
            'request_id' => @request_id,
            'category' => 'ActiveRecord',
            'duration' => 11.9,
          },
        ],
      ],
      sorted_results
    )
    assert_empty errors
  end

  test 'Completed line with some extra durations' do
    @record[:messages] = 'Completed 200 OK in 17ms (Views: 12.3ms | ActiveRecord: 45.6ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        @status_output,
        [
          @time,
          'finish.durations',
          {
            'request_id' => @request_id,
            'category' => 'ActiveRecord',
            'duration' => 45.6,
          },
        ],
        [
          @time,
          'finish.durations',
          {
            'request_id' => @request_id,
            'category' => 'Views',
            'duration' => 12.3,
          },
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
