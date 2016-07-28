#!/usr/bin/env ruby

require 'ghost-chef'

$:.unshift File.expand_path('../lib', File.dirname(__FILE__))
require 'config'

def environment
  'QA' # or Production. Should be a parameter passed in.
end

begin
  puts "Retrieving VPC"
  vpc = retrieve_vpc(tags) or abort "Cannot find VPC"

  puts "Retrieving Web security group"
  web_security_group = retrieve_security_group(
    vpc, [app_env, 'Web'].join('-'),
  ) or abort "Cannot find Web Security group"

  puts "Retrieving ELB"
  elb = GhostChef::LoadBalancer.retrieve_elb(elb_name) or abort "Cannot find ELB #{elb_name}"

  puts "Retrieving existing ASGs"
  existing_groups = GhostChef::AutoScaling.retrieve_auto_scaling_groups(
    load_balancer_names: elb.load_balancer_name,
  )

  puts "Ok"
rescue Aws::Errors::ServiceError => e
  puts "#{e.class}: #{e}"
  abort 'FAILED'
end
