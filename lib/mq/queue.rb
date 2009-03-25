class MQ
  class Queue
    
    def initialize(mq, name, opts = {})
      @mq         = mq
      @opts       = opts
      @bindings ||= {}

      @mq.queues[@name = name] ||= self
      @mq.send Protocol::Queue::Declare.new({ :queue => name, :nowait => true }.merge(opts))
    end
    attr_reader :name

    def bind(exchange, opts = {})
      exchange = exchange.respond_to?(:name) ? exchange.name : exchange
      @bindings[exchange] = opts

      @mq.send(
        Protocol::Queue::Bind.new(
          { :queue => name, :exchange => exchange, :routing_key => opts.delete(:key), :nowait => true }.merge(opts)
        )
      )
      self
    end

    def unbind(exchange, opts = {})
      exchange = exchange.respond_to?(:name) ? exchange.name : exchange
      @bindings.delete exchange

      @mq.send(
        Protocol::Queue::Unbind.new(
          { :queue => name, :exchange => exchange, :routing_key => opts.delete(:key), :nowait => true }.merge(opts)
        )
      )
      self
    end

    def delete(opts = {})
      @mq.send(
        Protocol::Queue::Delete.new({ :queue => name, :nowait => true }.merge(opts))
      )
      @mq.queues.delete @name
      nil
    end

    def pop(opts = {}, &blk)
      @mq.get_queue do |q|
        q.push(self)
        @mq.send(
          Protocol::Basic::Get.new({ :queue => name, :consumer_tag => name, :no_ack => !opts.delete(:ack), :nowait => true }.merge(opts))
        )
      end 

      self
    end

    def subscribe(opts = {}, &blk)
      @consumer_tag = "#{name}-#{Kernel.rand(999_999_999_999)}"
      @mq.consumers[@consumer_tag] = self

      raise Error, 'already subscribed to the queue' if subscribed?

      @on_msg      = blk
      @on_msg_opts = opts

      @mq.send(
        Protocol::Basic::Consume.new(
          {:queue => name, :consumer_tag => @consumer_tag, :no_ack => !opts.delete(:ack), :nowait => true }.merge(opts)
        )
      )
      self
    end

    def unsubscribe(opts = {}, &blk)
      @on_msg    = nil
      @on_cancel = blk
      @mq.send(Protocol::Basic::Cancel.new({ :consumer_tag => @consumer_tag }.merge(opts)))
      self
    end

    def publish(data, opts = {})
      exchange.publish(data, opts)
    end
    
    def subscribed?
      !!@on_msg
    end

    def receive(headers, body)
      headers = MQ::Header.new(@mq, headers)

      if cb = (@on_msg || @on_pop)
        cb.call *(cb.arity == 1 ? [body] : [headers, body])
      end
    end

    def status(opts = {}, &blk)
      @on_status = blk
      @mq.send(Protocol::Queue::Declare.new({ :queue => name, :passive => true }.merge(opts)))
      self
    end

    def recieve_status(declare_ok)
      if @on_status
        m, c = declare_ok.message_count, declare_ok.consumer_count
        @on_status.call *(@on_status.arity == 1 ? [m] : [m, c])
        @on_status = nil
      end
    end

    def cancelled
      @on_cancel.call if @on_cancel
      @on_cancel = @on_msg = nil
      @mq.consumers.delete @consumer_tag
      @consumer_tag = nil
    end

    def reset
      @deferred_status = nil
      initialize @mq, @name, @opts

      binds = @bindings
      @bindings = {}
      binds.each{|ex,opts| bind(ex, opts) }

      if blk = @on_msg
        @on_msg = nil
        subscribe(@on_msg_opts, &blk)
      end

      if @on_pop
        pop(@on_pop_opts, &@on_pop)
      end
    end
  
  private
    def exchange
      @exchange ||= Exchange.new(@mq, :direct, '', :key => name)
    end
  end
end
