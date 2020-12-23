# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestStartedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf 'conf.d/request_started.conf'

  sub_test_case 'Started line' do
    test 'x1' do
      request_id = timestamp
      record = {
        request_id: request_id,
        severity: 'INFO',
        messages: 'Started GET "/foos/index?bar=baz" for 127.0.0.1 at 2020-12-20 19:47:36 +0900',
      }
      time = Time.now
      post(record: record, time: time)

      assert_equal(
        [
          [
            time,
            'finish.requests',
            {
              'request_id' => request_id,
              'http_method' => 'GET',
              'http_path_query' => '/foos/index?bar=baz',
            },
          ],
        ],
        results
      )
      assert_empty errors
    end
  end
end
