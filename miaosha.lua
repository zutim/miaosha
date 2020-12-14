
--获取get或post参数--------------------

local request_method = ngx.var.request_method
local args = nil
local param = nil
--获取参数的值
--获取秒杀下单的用户id
if "GET" == request_method then
    args = ngx.req.get_uri_args()
elseif "POST" == request_method then
    ngx.req.read_body()
    args = ngx.req.get_post_args()
end
user_id = args["user_id"]
--用户身份判断--省略
--用户能否下单--省略

--关闭redis的函数--------------------

local function close_redis(redis_instance)
    if not redis_instance then
        return
    end
    local ok,err = redis_instance:close();
    if not ok then
        ngx.say("close redis error : ",err);
    end
end

--引入cjson类--------------------
--local cjson = require "cjson"


--连接redis--------------------

local redis = require("resty.redis");
--local redis = require "redis"
-- 创建一个redis对象实例。在失败，返回nil和描述错误的字符串的情况下
local redis_instance = redis:new();
--设置后续操作的超时（以毫秒为单位）保护，包括connect方法
redis_instance:set_timeout(1000)
--建立连接
local ip = '127.0.0.1'
local port = 6379
--尝试连接到redis服务器正在侦听的远程主机和端口
local ok,err = redis_instance:connect(ip,port)
if not ok then
    ngx.say("connect redis error : ",err)
    return close_redis(redis_instance);
end




-- 加载nginx—lua限流模块
local limit_req = require "resty.limit.req"
-- 这里设置rate=50个请求/每秒，漏桶桶容量设置为1000个请求
-- 因为模块中控制粒度为毫秒级别，所以可以做到毫秒级别的平滑处理
local lim, err = limit_req.new("my_limit_req_store", 50, 1000)
if not lim then
    ngx.log(ngx.ERR, "failed to instantiate a resty.limit.req object: ", err)
    return ngx.exit(501)
end

local key = ngx.var.binary_remote_addr
local delay, err = lim:incoming(key, true)


ngx.say("计算出来的延迟时间是：")
ngx.say(delay)

--if ( delay <0 or delay==nil ) then
    --return ngx.exit(502)
--end

--先死这个值为-1, 就是先不限流, 先测试下面的乐观锁代码。
--delay = -1

-- 1000以外的就溢出，回绝掉，比如100000个人来抢购，那么100000-1000的请求直接nginx回绝
if not delay then
    if err == "rejected" then
        return ngx.say("1000以外的就溢出")
        -- return ngx.exit(502)
    end
    ngx.log(ngx.ERR, "failed to limit req: ", err)
    return ngx.exit(502)
end

-- 计算出要等很久，比如要等10秒的， 也直接不要他等了。要买家直接回家吃饭去
if ( delay >10) then
    ngx.say("抢购超时")
    return
end

--先到redis里面添加sku_num键（参与秒杀的该商品的数量）
--并到redis里面添加watch_key键（用于做乐观锁之用）

local resp, err = redis_instance:get("sku_num")
resp = tonumber(resp)
ngx.say("数量：")
ngx.say(resp)
if (resp > 0) then
    --ngx.say("抢购成功")
    redis_instance:watch("watch_key");
    -- ngx.sleep(1)
    local ok, err = redis_instance:multi();
    local sku_num = tonumber(resp) - 1;
    ngx.say("goods_num:")
    ngx.say(sku_num)
    redis_instance:set("sku_num",sku_num);
    redis_instance:set("watch_key",sku_num);
    ans, err = redis_instance:exec()
    ngx.say("ans：")
    ngx.say(ans)
    ngx.say(tostring(ans))
    ngx.say("--")
    if (tostring(ans) == "userdata: NULL") then
        ngx.say("抢购失败,慢一丁点")
        -- return
    else
        ngx.say("抢购成功")
        -- return
    end

else
    ngx.say("抢购失败,手慢了")
    -- return
end

--下面这行代码是进入正式下单;
-- ngx.exec('/create_order'); --注意这行代码前面不能执行ngx.say()



--[[
--每个用户限购1个,判断用户是否已经抢购过了的参考代码逻辑思路如下（具体过程略,前端缓存中也有这个类似的判断用于限制对后端的请求）：

建一张用于保存已经抢购成功了的用户的redis哈希表

抢购前判断是否在该表中
local res, err = redis_instance:hmget("myhash", "user_id")
抢购成功则保存到该表
local res, err = redis_instance:hmset("myhash", "user_id", "1")
--]]