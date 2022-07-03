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
    "stringy = 0.7-0",
}

build = {
   type = "builtin",
   modules = {
      ["shenyu.register.etcd"] = "lib/shenyu/register/etcd.lua",
      ["shenyu.register.nacos"] = "lib/shenyu/register/nacos.lua",
      ["shenyu.register.balancer"] = "lib/shenyu/register/balancer.lua",
      ["shenyu.register.consul"] = "lib/shenyu/register/consul.lua",
      ["shenyu.register.zookeeper"] = "lib/shenyu/register/zookeeper.lua",
      ["shenyu.register.zookeeper.connection"] = "lib/shenyu/register/zookeeper/connection.lua",
      ["shenyu.register.zookeeper.zk_client"] = "lib/shenyu/register/zookeeper/zk_client.lua",
      ["shenyu.register.zookeeper.zk_cluster"] = "lib/shenyu/register/zookeeper/zk_cluster.lua",
      ["shenyu.register.zookeeper.zk_const"] = "lib/shenyu/register/zookeeper/zk_const.lua",
      ["shenyu.register.zookeeper.zk_proto"] = "lib/shenyu/register/zookeeper/zk_proto.lua",
      ["shenyu.register.core.string"] = "lib/shenyu/register/core/string.lua",
      ["shenyu.register.core.struct"] = "lib/shenyu/register/core/struct.lua",
      ["shenyu.register.core.utils"] = "lib/shenyu/register/core/utils.lua",
   }
}
