#!/usr/bin/env ruby

$:.unshift "/home/rob/devel/ghost-chef/lib"

require 'ghost-chef'

$:.unshift File.expand_path('../lib', File.dirname(__FILE__))
require 'config'

def environment
  'QA' # or Production. Should be a parameter passed in.
end

def pagerduty_link
  abort "Need to look up the PD link"
end

#TODO
# 1. PD link
# 2. Create 4 subnets (a,b,d,e) for RDS purposes within the VPC.

begin
  # Ensure the right VPC exists
  puts "\nVPC:"

  puts "\tEnsuring VPC ..."
  vpc = ensure_vpc(
    vpc_subnet(environment),
    tags,
    dns: {
      support: true,
      hostnames: true,
    },
  )

  # Ensure the VPC has subnets in the right AZ(s)
  puts "\tEnsuring Subnets ..."
  subnets = {}
  avail_zones(environment).each do |zone_name, cidr_block|
    subnets[zone_name] = ensure_subnet(
      vpc, zone_name, cidr_block,
      tags(Name: [app_env, zone_name].join('-')),
    )
  end

  puts "\tEnsuring Internet Gateway ..."
  inet_gway = ensure_internet_gateway(tags)

  puts "\tEnsuring VPC is attached to Internet Gateway ..."
  ensure_vpc_attached_gateway(vpc, inet_gway)

  puts "\tEnsuring the VPC's route table connects to the gateway"
  ensure_vpc_routes_to_gateway(vpc, inet_gway)

  # Ensure there is a good security group for the ELB
  puts "\tEnsuring ELB security group ..."
  elb_security_group = ensure_security_group(
    vpc,
    [app_env, 'ELB'].join('-'),
    "#{app_env} ELB Security Group",
    tags(Name: [app_env, 'ELB'].join('-')),
  )

  # Ensure there is a good security group for the EC2 instances
  puts "\tEnsuring Web security group ..."
  web_security_group = ensure_security_group(
    vpc,
    [app_env, 'Web'].join('-'),
    "#{app_env} Web Security Group",
    tags(Name: [app_env, 'Web'].join('-')),
  )

  puts "\tEnsuring RDS security group ..."
  rds_security_group = ensure_security_group(
    vpc,
    [app_env, 'RDS'].join('-'),
    "#{app_env} RDS Security Group",
    tags(Name: [app_env, 'RDS'].join('-')),
  )

  # Ensure the security groups have the appropriate ingresses/egresses to each
  # other and the rest of the world.
  puts "\tEnsuring the appropriate ingress/egress rules (ELB)"
  ensure_security_group_rules(
    elb_security_group,
    ingress: [
      { port: http_port, source: Everyone },
    ],
    egress: [
      { port: http_port, group: web_security_group.group_id },
    ],
  )

  puts "\tEnsuring the appropriate ingress/egress rules (Web)"
  ensure_security_group_rules(
    web_security_group,
    ingress: [
      { port: http_port, group: elb_security_group.group_id },
    ],
    egress: [
      { port: pg_port, group: rds_security_group.group_id },
    ],
  )

  puts "\tEnsuring the appropriate ingress/egress rules (RDS)"
  ensure_security_group_rules(
    rds_security_group,
    ingress: [
      { port: pg_port, group: web_security_group.group_id },
    ],
  )

  puts "\nELB:"

  # Ensure the SSL certificate exists
  puts "\tEnsuring the SSL certificate ..."
  cert = GhostChef::Certificates.ensure_certificate('*.qa.place.com')

  # Ensure the ELB exists
  #   and is associated with the right subnets / right AZ(s)
  #   and is associated with the SSL certificate(s)
  puts "\tEnsuring ELB ..."
  elb = GhostChef::LoadBalancer.ensure_elb(
    elb_name,
    [
      {
        protocol: 'HTTPS',
        load_balancer_port: https_port,
        instance_protocol: 'HTTP',
        instance_port: http_port,
        ssl_certificate_id: cert.certificate_arn,
      },
    ],
    subnets: [ subnets['us-east-1d'].subnet_id ],
    security_groups: [ elb_security_group ],
    tags: tags,
  )

  puts "\tEnsuring ELB DNS name ..."
  GhostChef::Route53.ensure_dns_for_elb('secure.qa.place.com', elb)

  puts "\tTODO: Ensuring there is an escalation action for alarms ..."
  #topic = ensure_topic('PagerDuty')
  #ensure_topic_subscription(topic, pagerduty_link)

  puts "\tTODO: Ensuring the ELB is monitored ..."
  {
    unhealthy_hosts: {
      statistic: :minimum,
      threshold: 1,
      periods: 1,
    },
    backend_errors: {
      statistic: :total,
      threshold: 100,
      periods: 2,
    },
  }.each do |metric, params|
    puts "\tTODO: Adding alarm for #{metric}"
    #ensure_alarm(params.merge(
    #  name: elb_name,
    #  type: :elb,
    #  metric: metric,
    #  action: topic.topic_arn,
    #))
  end

  puts "\nEC2:"

  puts "\tEnsuring instance profile ..."
  instance_profile = GhostChef::IAM.ensure_instance_profile(
    instance_profile_name(environment),
  )

  puts "\nRDS:"

  puts "\tEnsuring RDS parameter group ..."
  parameter_group = GhostChef::Database.ensure_parameter_group(
    app_env.downcase,
    engine: 'postgres',
    version: '9.4',
    tags: tags,
  )

  puts "\tEnsuring RDS option group ..."
  option_group = GhostChef::Database.ensure_option_group(
    app_env.downcase,
    engine: 'postgres',
    version: '9.4',
    tags: tags,
  )

  puts "\tEnsuring RDS subnet group ..."
  db_subnet_group = GhostChef::Database.ensure_subnet_group(
    app_env.downcase,
    subnets: subnets.values,
    tags: tags,
  )

  # Ensure the RDS instance is created
  puts "\tEnsuring database ..."
  database = GhostChef::Database.ensure_database(
    app_env.downcase,

    db_instance_class: 'db.m3.medium',
    multi_az: false,

    engine: 'postgres',
    engine_version: '9.4.5',
    auto_minor_version_upgrade: true,

    allocated_storage: 20,
    storage_type: 'standard',
    storage_encrypted: true,

    db_name: 'neil2',
    master_username: 'dba', # 1-63
    master_user_password: 'mypassword', # 8-128

    parameter_group: parameter_group,
    option_group: option_group,
    vpc_security_groups: [ rds_security_group ],
    subnet_group: db_subnet_group,
    publicly_accessible: true,

    backup_retention_period: 0,
    copy_tags_to_snapshot: true,

    tags: tags,
  )

  puts "\tWaiting for database to become available"
  GhostChef::Database.waitfor_database_available(database)

  puts "\nOk"
rescue Aws::Errors::ServiceError => e
  puts "#{e.class}: #{e}"
  abort 'FAILED'
end
