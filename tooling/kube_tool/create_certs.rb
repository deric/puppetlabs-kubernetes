require 'fileutils'
require 'openssl'
require 'json'
require 'base64'
require_relative 'clean_up.rb'

class CreateCerts

  def initialize(opts)
    @opts = opts
    @yaml_file = 'kubernetes.yaml'
    @eyaml_file = 'kubernetes.eyaml'
    exp = @opts['expiry']
    exp ||=  '5 years'
    @expiry = expiration(exp)
  end

  def write_json(data, filename)
    File.open(filename, "w+") { |file| file.write(data.to_json) }
  end

  def append_yaml(data, filename)
    File.open(filename, "a") { |file| file.write(data.to_yaml) }
  end

  def store_secret(data, secrets, key, file)
    value = File.read(file)
    if @opts[:eyaml]
      secrets[key] = to_eyaml(value)
    else
      data[key] = value
    end
  end

  def to_eyaml(secret)
    "DEC::PKCS7[#{secret}]!"
  end

  def etcd_ca
    puts "Creating etcd ca"
    CleanUp.all(['ca-conf.json', 'ca-csr.json', 'ca-key.pem', 'ca-key.pem'])
    csr = { "CN": "etcd", "key": {"algo": "rsa", "size": @opts[:key_size] }}
    conf = { "signing": { "default": { "expiry": @expiry }, "profiles": { "server": { "expiry": @expiry, "usages": [ "signing", "key encipherment", "server auth", "client auth" ] }, "client": { "expiry": @expiry, "usages": [ "signing", "key encipherment", "client auth" ] }, "peer": { "expiry": @expiry, "usages": [ "signing", "key encipherment", "server auth", "client auth" ] } } } }
    write_json(csr, 'ca-csr.json')
    write_json(conf, 'ca-conf.json')
    system('cfssl gencert -initca ca-csr.json | cfssljson -bare ca')
    FileUtils.rm_f('ca.csr')
    data = {}
    secrets = {}
    data['kubernetes::etcd_ca_crt'] = File.read('ca.pem')
    store_secret(data, secrets, 'kubernetes::etcd_ca_key', 'ca-key.pem')
    append_yaml(data, @yaml_file)
    append_yaml(secrets, @eyaml_file) if @opts[:eyaml]
  end

  def etcd_clients
    puts "Creating etcd client certs"
    csr = { "CN": "client", "hosts": [""], "key": { "algo": "rsa", "size": @opts[:key_size] } }
    write_json(csr, 'kube-etcd-csr.json')
    system("cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-conf.json -profile client kube-etcd-csr.json | cfssljson -bare client")
    FileUtils.rm_f('kube-etcd-csr.csr')
    data = {}
    secrets = {}
    data['kubernetes::etcdclient_crt'] = File.read("client.pem")
    store_secret(data, secrets, 'kubernetes::etcdclient_key', 'client-key.pem')
    append_yaml(data, @yaml_file)
    append_yaml(secrets, @eyaml_file) if @opts[:eyaml]
  end

  def etcd_certificates
    etcd_servers = @opts[:etcd_initial_cluster].split(",")
    etcd_server_ips = []
    etcd_servers.each do | servers |
      server = servers.split(":")
      etcd_server_ips.push(server[1])
    end

    etcd_servers.each do | servers |
      server = servers.split(":")
      hostname = server[0]
      ip = server[1]
      puts "Creating etcd peer and server certificates"
      csr = { "CN": "etcd-#{hostname}", "hosts": etcd_server_ips, "key": { "algo": "rsa", "size": @opts[:key_size] }}
      write_json(csr, 'config.json')
      system("cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-conf.json -profile server --hostname=#{etcd_server_ips * ","},#{hostname} config.json | cfssljson -bare #{hostname}-server")
      system("cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-conf.json -profile peer --hostname=#{ip},#{hostname} config.json | cfssljson -bare #{hostname}-peer")
      system("cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-conf.json -profile client --hostname=#{ip},#{hostname} config.json | cfssljson -bare #{hostname}-client")
      FileUtils.rm_f('etcd-server.csr')
      data = {}
      secrets = {}

      key_client = File.read("#{hostname}-client-key.pem")
      data['kubernetes::etcdserver_crt'] = File.read("#{hostname}-server.pem")
      store_secret(data, secrets, 'kubernetes::etcdserver_key', "#{hostname}-server-key.pem")
      data['kubernetes::etcdpeer_crt'] = File.read("#{hostname}-peer.pem")
      store_secret(data, secrets, 'kubernetes::etcdpeer_key', "#{hostname}-peer-key.pem")
      data['kubernetes::etcdclient_crt'] = File.read("#{hostname}-client.pem")
      store_secret(data, secrets, 'kubernetes::etcdclient_key', "#{hostname}-client-key.pem")
      append_yaml(data, "#{hostname}.yaml")
      append_yaml(secrets, "#{hostname}.eyaml") if @opts[:eyaml]
    end
  end

  def kube_ca
    puts "Creating kube ca"
    CleanUp.all(['ca-conf.json', 'ca-csr.json', 'ca-key.pem', 'ca-key.pem'])
    csr = { "CN": "kubernetes", "key": {"algo": "rsa", "size": @opts[:key_size] }}
    conf = { "signing": { "default": { "expiry": @expiry }, "profiles": { "server": { "expiry": @expiry, "usages": [ "signing", "key encipherment", "server auth", "client auth" ] }, "client": { "expiry": @expiry, "usages": [ "signing", "key encipherment", "client auth" ] }, "peer": { "expiry": @expiry, "usages": [ "signing", "key encipherment", "server auth", "client auth" ] } } } }
    write_json(csr, 'ca-csr.json')
    File.open("ca-conf.json", "w+") { |file| file.write(conf.to_json) }
    system('cfssl gencert -initca ca-csr.json | cfssljson -bare ca')
    system("openssl x509 -pubkey -in ca.pem | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' > discovery_token_hash")
    FileUtils.rm_f('ca.csr')
    data = {}
    secrets = {}
    discovery_token_hash = File.read('discovery_token_hash').gsub("\n",'').strip
    data['kubernetes::kubernetes_ca_crt'] = File.read('ca.pem')
    store_secret(data, secrets, 'kubernetes::kubernetes_ca_key', 'ca-key.pem')
    data['kubernetes::discovery_token_hash'] = discovery_token_hash
    FileUtils.rm_f('discovery_token_hash.csr')
    append_yaml(data, @yaml_file)
    append_yaml(secrets, @eyaml_file) if @opts[:eyaml]
  end

  def kube_front_proxy_ca
    puts "Creating kube front-proxy ca"
    CleanUp.all(['front-proxy-ca-conf.json', 'front-proxy-ca-csr.json', 'front-proxy-ca-key.pem', 'front-proxy-ca-key.pem'])
    csr = { "CN": "front-proxy-ca", "key": {"algo": "rsa", "size": @opts[:key_size] }}
    conf = { "signing": { "default": { "expiry": "87600h" }}}
    write_json(csr, 'front-proxy-ca-csr.json')
    write_json(conf, 'front-proxy-ca-conf.json')
    system('cfssl gencert -initca front-proxy-ca-csr.json | cfssljson -bare front-proxy-ca')
    FileUtils.rm_f('front-proxy-ca.csr')
    data = {}
    secrets = {}
    data['kubernetes::kubernetes_front_proxy_ca_crt'] = File.read("front-proxy-ca.pem")
    store_secret(data, secrets, 'kubernetes::kubernetes_front_proxy_ca_key', 'front-proxy-ca-key.pem')
    append_yaml(data, @yaml_file)
    append_yaml(secrets, @eyaml_file) if @opts[:eyaml]
  end

  def sa
    puts "Creating service account certs"
    key = OpenSSL::PKey::RSA.new @opts[:key_size]
    open 'sa-key.pem', 'w' do |io|
      io.write key.to_pem
    end
    open 'sa-pub.pem', 'w' do |io|
      io.write key.public_key.to_pem
    end
    data = {}
    secrets = {}
    data['kubernetes::sa_pub'] = File.read('sa-pub.pem')
    store_secret(data, secrets, 'kubernetes::sa_key', 'sa-key.pem')
    append_yaml(data, @yaml_file)
    append_yaml(secrets, @eyaml_file) if @opts[:eyaml]
  end

  # Convert string e.g. `5y` to expiration in hours
  def expiration(expiry)
    pattern = Regexp.new('(\d)\s?([a-zA-Z]+)')
    unless pattern.match?(expiry)
      raise "Unknown expiry format '#{expiry}'"
    else
      m = expiry.match(pattern)
      case m[2]
      when 'y',/year(s?)/
        return "#{m[1].to_i * 365 * 24}h"
      end
    end
  end
end
