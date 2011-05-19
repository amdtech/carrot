require File.dirname(File.expand_path(__FILE__)) + '/../carrot'

#Carrot.logging = true
consumer1 = Carrot.queue('tasty')
consumer2 = Carrot.queue('nomnom')

fanout = Carrot.fanout("carrot")

consumer1.bind(fanout)
consumer2.bind(fanout)

fanout.publish('foo')

msg = consumer1.pop(:ack => true)
puts "consumer 1: #{msg}"

consumer2.pop(:ack => true)
puts "consumer 2: #{msg}"

Carrot.stop
