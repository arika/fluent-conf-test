# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestCompletedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf 'conf.d/log.conf'

  setup do
    @request_id = timestamp
    @record = {
      request_id: @request_id,
      severity: 'INFO',
    }
    @time = Time.now
  end
end
