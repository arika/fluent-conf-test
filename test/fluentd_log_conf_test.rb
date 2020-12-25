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
    assert_empty errors

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
    assert_empty errors
  end

  test 'log with ActiveRecord model duration' do
    @record['messages'] = '  Post Load (0.2ms)  ' \
                          'SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? LIMIT ?  [["id", 1], ["LIMIT", 1]]'
    post(record: @record, time: @time)

    assert_equal(
      [
        [
          @time,
          'finish.log_durations',
          @record.merge(
            'category' => 'ActiveRecord',
            'target' => 'Post',
            'duration' => 0.2
          ),
        ],
        [@time, 'finish.logs', @record],
      ],
      sorted_results_without_random
    )
    assert_empty errors
  end

  test 'log with ActiveRecord model association duration' do
    @record['messages'] = '  SQL (0.1ms)  ' \
                          'SELECT "posts"."id" AS t0_r0, "posts"."title" AS t0_r1, "posts"."body" AS t0_r2, ' \
                          '"posts"."created_at" AS t0_r3, "posts"."updated_at" AS t0_r4, ' \
                          '"comments"."id" AS t1_r0, "comments"."post_id" AS t1_r1, "comments"."body" AS t1_r2, ' \
                          '"comments"."created_at" AS t1_r3, "comments"."updated_at" AS t1_r4 FROM "posts" ' \
                          'INNER JOIN "comments" ON "comments"."post_id" = "posts"."id"'
    post(record: @record, time: @time)

    assert_equal(
      [
        [
          @time,
          'finish.log_durations',
          @record.merge(
            'category' => 'ActiveRecord',
            'target' => 'SQL',
            'duration' => 0.1
          ),
        ],
        [@time, 'finish.logs', @record],
      ],
      sorted_results_without_random
    )
  end

  test 'log with ActiveRecord other duration' do
    @record['messages'] = '   (0.2ms)  ' \
                          'SELECT COUNT(*) FROM "comments" WHERE "comments"."post_id" = ?  [["post_id", 1]]'
    post(record: @record, time: @time)

    assert_equal(
      [
        [
          @time,
          'finish.log_durations',
          @record.merge(
            'category' => 'ActiveRecord',
            'target' => 'SQL',
            'duration' => 0.2
          ),
        ],
        [@time, 'finish.logs', @record],
      ],
      sorted_results_without_random
    )
  end

  test 'ignore CACHE duration' do
    @record['messages'] = '  CACHE Post Load (0.0ms)  SELECT "posts".* FROM "posts"'
    post(record: @record, time: @time)

    assert_equal(
      [
        [@time, 'finish.logs', @record],
      ],
      results_without_random
    )
    assert_empty errors
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
