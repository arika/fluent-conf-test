# frozen_string_literal: true

require_relative 'test_helper'

class FluentdRequestCompletedConfTest < Test::Unit::TestCase
  include FluentdConfTestHelper

  fluentd_conf conf_path: 'fluentd/conf.d/log.conf', stub_labels: %w[OUTPUT]

  setup do
    @record = {
      'request_id' => timestamp,
      'severity' => 'INFO',
    }
    @time = Time.now
  end

  test 'log with rendering duration' do
    @record['messages'] = '  Rendered foos/index.html.erb within layouts/application (0.9ms)'
    post(record: @record, time: @time)

    assert_equal(
      [
        @record.merge(
          'duration' => 0.9,
          'category' => 'Views',
          'target' => 'foos/index.html.erb',
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.logs')
    )
    assert_equal 1, outputs.size
    assert_empty error_outputs
  end

  test 'log with ActiveRecord model duration' do
    @record['messages'] = '  Post Load (0.2ms)  ' \
                          'SELECT "posts".* FROM "posts" WHERE "posts"."id" = ? LIMIT ?  [["id", 1], ["LIMIT", 1]]'
    post(record: @record, time: @time)

    assert_equal(
      [
        @record.merge(
          'duration' => 0.2,
          'category' => 'ActiveRecord',
          'target' => 'Post',
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.logs')
    )
    assert_equal 1, outputs.size
    assert_empty error_outputs
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
        @record.merge(
          'duration' => 0.1,
          'category' => 'ActiveRecord',
          'target' => 'SQL',
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.logs')
    )
    assert_equal 1, outputs.size
    assert_empty error_outputs
  end

  test 'log with ActiveRecord other duration' do
    @record['messages'] = '   (0.2ms)  ' \
                          'SELECT COUNT(*) FROM "comments" WHERE "comments"."post_id" = ?  [["post_id", 1]]'
    post(record: @record, time: @time)

    assert_equal(
      [
        @record.merge(
          'duration' => 0.2,
          'category' => 'ActiveRecord',
          'target' => '',
        ),
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.logs')
    )
    assert_equal 1, outputs.size
    assert_empty error_outputs
  end

  data(
    'simple log' => 'simple log',
    'CACHE duration' => '  CACHE Post Load (0.0ms)  SELECT "posts".* FROM "posts"',
    'unknwon duration' => '  unknown duration (0.9ms)',
  )
  test 'simple log' do |message|
    @record['messages'] = message
    post(record: @record, time: @time)

    assert_equal(
      [
        @record.merge,
      ],
      outputs(label: 'OUTPUT', time: @time, tag: 'finish.logs')
    )
    assert_equal 1, outputs.size
    assert_empty error_outputs
  end
end
