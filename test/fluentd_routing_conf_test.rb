# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestCompletedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf conf_path: 'fluentd/conf.d/routing.conf', stub_labels: %w[REQUEST_STARTED REQUEST_COMPLETED LOG]

  setup do
    @record = {
      'request_id' => timestamp,
      'severity' => 'INFO',
      'messages' => 'test',
    }
    @time = Time.now
  end

  test 'copy and relabel' do
    post(record: @record, time: @time)

    %w[REQUEST_STARTED REQUEST_COMPLETED LOG].each do |label|
      assert_equal(
        [@record],
        outputs(label: label, time: @time, tag: 'app'),
        "record should be copied and relabeled @#{label}"
      )
    end
    assert_equal 3, outputs.size
    assert_empty error_outputs
  end
end
