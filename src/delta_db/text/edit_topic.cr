# src/delta_db/text/edit_topic.cr
module DeltaDB
  module Text
    class EditTopic(T)
      class Subscription(T)
        @cancelled = false

        def initialize(@topic : EditTopic(T), @index : Int32)
        end

        def cancel : Nil
          return if @cancelled
          @topic.unsubscribe(@index)
          @cancelled = true
        end
      end

      @subscribers = [] of Proc(T, Nil)

      def publish(value : T) : Nil
        @subscribers.each { |sub| sub.call(value) }
      end

      def subscribe(&block : T -> Nil) : EditSubscription(T)
        @subscribers << block
        EditSubscription(T).new(self, @subscribers.size - 1)
      end

      protected def unsubscribe(index : Int32) : Nil
        @subscribers[index] = ->(_value : T) { }
      end
    end
  end
end
