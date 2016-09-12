require 'mdk'
$mdk = ::Quark::Mdk.start()

def main()
  ssn = $mdk.session()
  address = ssn.resolve_until(ARGV[0], "1.0.0", 10.0).address
  puts address
  $mdk.stop
end

main()
