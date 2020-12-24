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
  end

  test 'x' do
    assert true
  end

  test 'Completed line' do
    @record[:messages] = 'Completed 200 OK in 17ms (Views: 11.9ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        [
          @time,
          'finish.durations',
          {
            'request_id' => @request_id,
            'duration' => 11.9,
          },
        ],
      ],
      results
    )
    assert_empty errors
  end
end
