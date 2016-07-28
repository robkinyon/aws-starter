#!/usr/bin/env ruby

require 'ghost-chef'

thisdir = File.dirname(__FILE__)
$:.unshift File.expand_path('../lib', thisdir)

require 'config'

def environment
  'QA' # or Production. Should be a parameter passed in.
end

def ensure_vpc_subnet(zone, cidr_block)
  # Ensure the right VPC exists
  puts "Ensuring VPC ..."
  vpc = ensure_vpc(vpc_subnet(environment), tags)

  # Ensure the VPC has subnets in the right AZ(s)
  puts "Ensuring Subnet in #{zone} ..."
  subnet = ensure_subnet(
    vpc, zone, cidr_block,
    tags(Name: [app_env, zone].join('-')),
  )

  puts "Ensuring Internet Gateway ..."
  inet_gway = ensure_internet_gateway(tags)

  puts "Ensuring VPC is attached to Internet Gateway ..."
  ensure_vpc_attached_gateway(vpc, inet_gway)

  puts "Ensuring the VPC's route table connects to the gateway"
  ensure_vpc_routes_to_gateway(vpc, inet_gway)

  return [vpc, subnet]
rescue Aws::EC2::Errors::ServiceError => e
  puts "#{e.class}: #{e}"
  abort 'FAILED'
end

def retrieve_branch_sha
  if ARGV.length >= 1
    branch_name = ARGV.shift
    if !system "git rev-parse --quiet --verify #{branch_name} >/dev/null"
      abort "#{branch_name} is not a real branch"
    end
  else
    branch_name = %x(git rev-parse --abbrev-ref HEAD).chomp
  end

  scm_id = %x(git rev-parse #{branch_name}).chomp

  return [branch_name, scm_id]
end

(vpc, subnet) = ensure_vpc_subnet('us-east-1a', '10.1.100.0/24')
(branch_name, scm_id) = retrieve_branch_sha
puts "#{branch_name} : #{scm_id}"

rv = system([
  'packer', 'build',
  '-var', "vpc_id='#{vpc.vpc_id}'",
  '-var', "subnet_id='#{subnet.subnet_id}'",
  '-var', "scm_id='#{scm_id}'",
  '-var', "scm_branch='#{branch_name}'",
  File.join(thisdir, 'appserver.json'),
].join(' '))

if rv
  puts "Ok"
else
  abort "Failed"
end
