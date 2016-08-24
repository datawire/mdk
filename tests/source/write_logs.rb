require 'mdk'
$mdk = ::Quark::Mdk.start()

def main()
  start = Time.now
  session = $mdk.session()
  session.trace("DEBUG")
  messages = []
  category = ARGV[0]
  sent_messages = ["hello critical " + category,
		   "hello debug " + category,
		   "hello error " + category,
		   "hello info " + category,
		   "hello warn " + category]

  $mdk._tracer.subscribe(
    Proc.new {|event|
      if Time.now - start > 60 then
        puts "Timeout"
        exit! 1
      end
      puts "got message #{event}"
      if (event.category == category) then
        messages.push(event.text)
      end
      if (messages.length == 5) then
        $mdk.stop
        messages.sort!
        if (messages != sent_messages) then
          puts "unexpected responses:"
          puts messages
          exit! 1
        else
          puts "got all messages"
          exit! 0
        end
      end
    })

  session.critical(category, sent_messages[0])
  session.debug(category, sent_messages[1])
  session.error(category, sent_messages[2])
  session.info(category, sent_messages[3])
  session.warn(category, sent_messages[4])
end

main()
