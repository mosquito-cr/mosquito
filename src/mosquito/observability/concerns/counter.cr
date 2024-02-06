module Mosquito::Observability::Counter
  def count(stage : Array(String | Symbol)) : Nil
    time = Time.utc

    month_key = "month=#{time.month}"
    day_key = "day=#{time.day}"
    hour_key = "hour=#{time.hour}"
    minute_key = "minute=#{time.minute}"
    second_key = "second=#{time.second}"

    Mosquito.backend.tap do |backend|
      daily_bucket = Backend.build_key :metrics, stage, :daily, month_key, day_key
      hourly_bucket = Backend.build_key :metrics, stage, :hourly, day_key, hour_key
      minutely_bucket = Backend.build_key :metrics, stage, :minutely, hour_key, minute_key
      secondly_bucket = Backend.build_key :metrics, stage, :secondly, minute_key, second_key

      backend.increment daily_bucket
      backend.increment hourly_bucket
      backend.increment minutely_bucket
      backend.increment secondly_bucket

      backend.delete daily_bucket, in: 2.days
      backend.delete hourly_bucket, in: 24.hours
      backend.delete minutely_bucket, in: 1.hour
      backend.delete secondly_bucket, in: 1.minute
    end
  end
end
