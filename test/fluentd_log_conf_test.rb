# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestCompletedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf 'conf.d/log.conf'

  setup do
    @request_id = timestamp
    @record = {
      'request_id' => timestamp,
      'severity' => 'INFO',
    }
    @time = Time.now
  end

  test 'simple log' do
    @record['messages'] = 'test log'
    post(record: @record, time: @time)

    assert_equal(
      [
        [@time, 'finish.logs', @record],
      ],
      results_without_random
    )

    random = results.dig(-1, -1, 'random')
    assert random
    assert_match(/\A0\.\d+\z/, random)

    assert_empty errors
  end

  test 'logs with duration' do
    [
      '  Rendered foos/index1.html.erb within layouts/application (0.1ms)',
      '  Rendered foos/index2.html.erb within layouts/application (0.2ms)',
    ].each do |messages|
      record = @record.merge('messages' => messages)
      post(record: record, time: @time)
    end

    assert_equal 4, results.size

    times = []
    request_ids = []
    random1 = []
    random2 = []
    results.each do |time, _tag, record|
      times << time
      request_ids << record['request_id']
      if /index1/.match?(record['messages'])
        random1 << record['random']
      else
        random2 << record['random']
      end
    end

    assert_equal 1, times.uniq.size
    assert_equal 1, request_ids.uniq.size

    assert_equal 2, random1.size
    assert_equal 1, random1.uniq.size

    assert_equal 2, random2.size
    assert_equal 1, random2.uniq.size
  end

  test 'log with rendering duration' do
    @record['messages'] = '  Rendered foos/index.html.erb within layouts/application (0.9ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        [
          @time,
          'finish.log_durations',
          @record.merge(
            'category' => 'Views',
            'target' => 'foos/index.html.erb',
            'duration' => 0.9
          ),
        ],
        [@time, 'finish.logs', @record],
      ],
      sorted_results_without_random
    )

    randoms = results.map { |(_, _, record)| record['random'] }.uniq
    assert_equal 1, randoms.size
    assert randoms.first

    assert_empty errors
  end

  test 'log with ActiveRecord model duration' do
  end

  test 'log with ActiveRecord model association duration' do
  end

  test 'log with ActiveRecord SQL duration' do
  end

  test 'log with unknown type duration' do
    @record['messages'] = '  unknown duration (0.9ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        [@time, 'finish.logs', @record],
      ],
      results_without_random
    )
    assert_empty errors
  end

  def results_without_random
    results.map do |time, tag, record|
      [
        time,
        tag,
        record.reject { |k,| k == 'random' },
      ]
    end
  end

  def sorted_results_without_random
    results_without_random.sort_by { |time, tag,| [time, tag] }
  end
end
