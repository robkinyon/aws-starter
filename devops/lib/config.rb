Everyone = '0.0.0.0/0'

def application
  'Some-Place'
end

def app_env
  [application, environment].join('-')
end

def vpc_subnet(env)
  {
    'Production' => '10.0.0.0/16',
    'QA'         => '10.1.0.0/16',
  }[env]
end

def avail_zones(env)
  {
    'Production' => {
      'us-east-1a' => '10.0.1.0/24',
      'us-east-1b' => '10.0.2.0/24',
      'us-east-1d' => '10.0.3.0/24',
      'us-east-1e' => '10.0.4.0/24',
    },
    'QA' => {
      'us-east-1d' => '10.1.1.0/24',
      'us-east-1a' => '10.1.2.0/24',
      'us-east-1b' => '10.1.3.0/24',
      'us-east-1e' => '10.1.4.0/24',
    },
  }[env]
end

def http_port
  80
end

def https_port
  443
end

def pg_port
  5432
end

def elb_name
  app_env
end

def instance_profile_name(env)
  ['insightcruises', env.downcase].join('-')
end

def tags(override={})
  {
    Name: app_env,
    application: application,
    environment: environment,
  }.merge(override)
end
