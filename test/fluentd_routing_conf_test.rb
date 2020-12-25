# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestCompletedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf 'conf.d/routing.conf', stub_labels: %w[@REQUEST_STARTED @REQUEST_COMPLETED @LOG]
end
