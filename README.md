incubator-shenyu-nginx
---

ShenYu(Incubator) is High-Performance Java API Gateway. 

ShenYu Nginx is an Nginx Upstream module for ShenYu instances discovery. The module will discover ShenYu instances to be upstream server of Nginx throght watching register, such as Etcd(supported), Apache Zookeeper(Todo), Nacos(Todo), and others.

## Getting Started

- Prerequisite:
1. Luarocks
2. OpenResty

### Build from source

The first, clone the source from Github.
```shell
git clone https://github.com/apache/incubator-shenyu-nginx
```

Then, build from source and install.
```shell
cd incubator-shenyu-nginx
luarocks make rockspec/shenyu-nginx-main-0.rockspec
```

Modify the Nginx configure, create and initialize the ShenYu Register to connect to targed register center.  Here is an example for Etcd.
```
init_worker_by_lua_block {
    local register = require("shenyu.register.etcd")
    register.init({
        balancer_type = "chash",
        etcd_base_url = "http://127.0.0.1:2379",
    })
}
```

1. `balancer_type` specify the balancer. It has supported `chash` and `round robin`.
2. `etcd_base_url` specify the Etcd server.

Modify the `upstream` to enable to update upstream servers dynamically. This case will synchorinze the ShenYu instance list with register center. 
And then pick one up for handling the request.
```
upstream shenyu {
    server 0.0.0.1; -- bad 
    
    balancer_by_lua_block {
        require("shenyu.register.etcd").pick_and_set_peer()
    }
}
```

Finally, restart OpenResty.
```shell
openresty -s reload
```

Here provides a completed [example](https://github.com/apache/incubator-shenyu-nginx/blob/main/example/nginx.conf).

## Contributor and Support

* [How to Contributor](https://shenyu.apache.org/community/contributor-guide)
* [Mailing Lists](mailto:dev@shenyu.apache.org)

## License

[Apache License 2.0](https://apache.org/licenses/LICENSE-2.0)
