module DeltaDB
  # A topic that broadcasts edit events to subscribers.
  #
  # Clean-room port of `deltadb::subscription::{EditTopic,EditSubscription}`.
  # Upstream is a broadcast channel with RAII-drop deregistration; Crystal has
  # no destructors, so unsubscribe is explicit via `cancel`.
  class EditTopic(T)
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

  # A handle to a subscription; `cancel` deregisters it.
  class EditSubscription(T)
    @cancelled = false

    def initialize(@topic : EditTopic(T), @index : Int32)
    end

    def cancel : Nil
      return if @cancelled
      @topic.unsubscribe(@index)
      @cancelled = true
    end
  end
end
