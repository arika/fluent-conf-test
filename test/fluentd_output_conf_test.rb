# frozen_string_literal: true

require_relative 'test_helper'

class FluentdOutputConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf conf_path: 'fluentd/output.conf'

  # sqlite3とかでやる?
  # それともdocker-compose?
end
