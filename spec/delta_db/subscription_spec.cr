# spec/delta_db/subscription_spec.cr
require "../spec_helper"

describe DeltaDB::Text::EditTopic do
  it "publishes to subscribers until cancelled" do
    topic = DeltaDB::Text::EditTopic(Int32).new
    received = [] of Int32
    sub = topic.subscribe { |v| received << v }

    topic.publish(1)
    topic.publish(2)
    received.should eq [1, 2]

    sub.cancel
    topic.publish(3)
    received.should eq [1, 2]
  end
end
