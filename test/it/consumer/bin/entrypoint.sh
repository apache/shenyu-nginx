#!/usr/bin/env sh

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License


inst_addr_1=$(curl -s http://instance1:9090/get)
if [[ -z "$inst_addr_1" ]]; then
  echo "failed to start instance 1."
  exit 129
fi

inst_addr_2=$(curl -s http://instance2:9090/get)
if [[ -z "$inst_addr_2" ]]; then
  echo "failed to start instance 2."
  exit 129
fi

rst=$(curl -Is http://gateway:8080/get | grep "HTTP/1.1 500")
if [[ -z "$rst" ]]; then
  echo "failed to set new environment for testing."
  exit 128
fi

rst=$(curl -Is http://instance1:9090/register | grep "HTTP/1.1 200")
echo $rst
if [[ -z "$rst" ]]; then
  echo "failed to register instance1 to etcd."
  exit 128
fi

rst=$(curl -Is http://instance2:9090/register | grep "HTTP/1.1 200")
echo $rst
if [[ -z "$rst" ]]; then
  echo "failed to register instance2 to etcd."
  exit 128
fi

sleep 5

curl -s http://gateway:8080/get

rst=$(curl -Is http://gateway:8080/get | grep "HTTP/1.1 200")
if [[ -z "$rst" ]]; then
  echo "shenyu nginx module did not work."
  exit 128
fi

inst1=$(curl -s http://gateway:8080/get)
inst2=$(curl -s http://gateway:8080/get)

[[ "$inst1" == "$inst2" ]] || (echo "validation failed" && exit 128)

# remove instance 1
rst=$(curl -Is http://instance1:9090/unregister | grep "HTTP/1.1 200")
if [[ -z "$rst" ]]; then
  echo "failed to unregister instance1 to etcd."
  exit 128
fi

sleep 5

rst=$(curl -Is http://gateway:8080/get | grep "HTTP/1.1 200")
if [[ -z "$rst" ]]; then
  echo "shenyu nginx module did not work right"
  exit 128
fi

rst=$(curl -s http://gateway:8080/get)
if [[ "$rst" == "$inst_addr_1" ]]; then
  echo "nginx module did remove unregister instance 1."
  exit 128
fi
rst=$(curl -s http://gateway:8080/get)
if [[ "$rst" == "$inst_addr_1" ]]; then
  echo "nginx module did remove unregister instance 1."
  exit 128
fi

echo "validation successful"
