# frozen_string_literal: true

require_relative 'test_helper'

class FluentdTest < Test::Unit::TestCase
  # integration test的なもの
  # FluentdConfTestHelperは使わない

  # sqlite3とかでやる?
  # それともdocker-compose?
  # output.confのテストとは違ってMySQL起動しといてね、でもよいかも?
end
