# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestStartedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf conf_path: 'fluentd/conf.d/request_started.conf', stub_labels: %w[OUTPUT]

  setup do
    @record = {
      'request_id' => timestamp,
      'severity' => 'INFO',
    }
    @time = Time.now
  end

  test 'Started line' do
    @record['messages'] = 'Started GET "/foos/index?bar=baz" for 127.0.0.1 at 2020-12-20 19:47:36 +0900'
    post(record: @record, time: @time)

    assert_equal(
      [
        @record.merge(
          'http_method' => 'GET',
          'http_path_query' => '/foos/index?bar=baz'
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.requests')
    )
    assert_equal 1, outputs.size
    assert_empty error_outputs
  end

  test 'Processing line' do
    @record['messages'] = 'Processing by FoosController#index as */*'
    post(record: @record, time: @time)

    assert_equal(
      [
        @record.merge(
          'controller' => 'FoosController',
          'action' => 'index'
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.controller_actions')
    )
    assert_equal 1, outputs.size
    assert_empty error_outputs
  end

  test 'Parameters line' do
    @record['messages'] = '  Parameters: {"bar"=>"baz"}'
    post(record: @record, time: @time)

    assert_equal(
      [
        @record.merge(
          'parameters' => '{"bar"=>"baz"}'
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.parameters')
    )
    assert_equal 1, outputs.size
    assert_empty error_outputs
  end

  test 'unexpected input' do
    @record['messages'] = 'Completed 200 OK in 17ms (Views: 11.9ms)'
    post(record: @record, time: @time)

    assert_empty outputs
    assert_empty error_outputs
  end
end
