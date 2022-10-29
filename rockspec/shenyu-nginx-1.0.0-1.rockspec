--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

package = "shenyu-nginx"
version = "1.0.0-1"
source = {
   url = "https://github.com/apache/shenyu-nginx",
   branch = "main",
}

description = {
   summary = "Discovery Apache Shenyu servers for Nginx",
   homepage = "https://github.com/apache/shenyu-nginx",
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
