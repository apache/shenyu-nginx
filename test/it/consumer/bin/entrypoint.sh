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

# 1: url, 2: condition, 3: message
send() {
  echo "send request to $1"
  curl -s -D ./head -o response $1
  rst=$(grep "$2" ./head)
  if [[ -z "rst" ]]; then
    echo "send $1 error: $3"
    cat ./head
    cat ./response
    exit 100
  fi
}

register() {
  inst=$1
  echo "${inst} registering..."
  inst_addr=$(curl -s http://${inst}:9090/register)
  if [[ -z "$inst_addr" ]]; then
    echo "failed to start ${inst}."
    exit 129
  fi
  echo "${inst} registered."
}

send "http://gateway:8080/get" "HTTP/1.1 500" "failed to set new environment for testing."

register "instance1"
register "instance2"

sleep 5

send "http://instance1:9090/get" "HTTP/1.1 200" "failed to request instance1."
send "http://instance2:9090/get" "HTTP/1.1 200" "failed to request instance2."

send "http://gateway:8080/get" "HTTP/1.1 200" "shenyu nginx module did not work."

echo "send requests to gateway."
inst1=$(curl -s http://gateway:8080/get)
inst2=$(curl -s http://gateway:8080/get)
if [[ "$inst1" == "$inst2" ]]; then
  echo "validation failed, inst1: ${inst1}, inst2: ${inst2}"
  exit 128
fi

# remove instance 1
send "http://instance1:9090/unregister" "HTTP/1.1 200" "failed to unregister instance1 to register center."

sleep 5

send "http://gateway:8080/get" "HTTP/1.1 200" "shenyu nginx module did not work right"

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

exit 200
