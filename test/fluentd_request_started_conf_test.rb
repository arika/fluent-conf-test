# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestStartedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf 'conf.d/request_started.conf'

  setup do
    @request_id = timestamp
    @record = {
      request_id: @request_id,
      severity: 'INFO',
    }
    @time = Time.now
  end

  test 'Started line' do
    @record[:messages] = 'Started GET "/foos/index?bar=baz" for 127.0.0.1 at 2020-12-20 19:47:36 +0900'
    post(record: @record, time: @time)

    assert_equal(
      [
        [
          @time,
          'finish.requests',
          {
            'request_id' => @request_id,
            'http_method' => 'GET',
            'http_path_query' => '/foos/index?bar=baz',
          },
        ],
      ],
      results
    )
    assert_empty errors
  end

  test 'Processing line' do
    @record[:messages] = 'Processing by FoosController#index as */*'
    post(record: @record, time: @time)

    assert_equal(
      [
        [
          @time,
          'finish.controller_actions',
          {
            'request_id' => @request_id,
            'controller' => 'FoosController',
            'action' => 'index',
          },
        ],
      ],
      results
    )
    assert_empty errors
  end

  test 'Parameters line' do
    @record[:messages] = '  Parameters: {"bar"=>"baz"}'
    post(record: @record, time: @time)

    assert_equal(
      [
        [
          @time,
          'finish.parameters',
          {
            'request_id' => @request_id,
            'parameters' => '{"bar"=>"baz"}'
          },
        ],
      ],
      results
    )
    assert_empty errors
  end

  test 'unexpected input' do
    @record[:messages] = 'Completed 200 OK in 17ms (Views: 11.9ms)'
    post(record: @record, time: @time)

    assert_empty results
    assert_empty errors
  end
end
