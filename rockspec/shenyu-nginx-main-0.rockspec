package = "shenyu-nginx"
version = "main-0"
source = {
   url = "https://github.com/apache/incubator-shenyu-nginx",
   branch = "main",
}

description = {
   summary = "Discovery Apache Shenyu servers for Nginx",
   homepage = "https://github.com/apache/incubator-shenyu-nginx",
   license = "Apache License 2.0"
}

dependencies = {
    "lua-resty-balancer >= 0.04",
    "lua-resty-http >= 0.15",
    "lua-cjson = 2.1.0.6-1",
}

build = {
   type = "builtin",
   modules = {
      ["shenyu.register.etcd"] = "lib/shenyu/register/etcd.lua",
      ["shenyu.register.nacos"] = "lib/shenyu/register/nacos.lua",
      ["shenyu.register.balancer"] = "lib/shenyu/register/balancer.lua",
   }
}
