chimu-claw.xyz 站点配置同步包
=========================================
生成时间: 2026-10-25 04:51:21
来源服务器: 本次会话直接修改的产物（已 nginx -t 通过并 reload 生效）

一、包含内容与目标路径
-----------------------------------------
1) nginx/chimu-claw.xyz.conf
   -> /www/server/panel/vhost/nginx/chimu-claw.xyz.conf
   改动 A：root 之后新增 gzip 段（gzip on / gzip_static on / gzip_vary / comp_level 6
            / min_length 1024 / gzip_types 含 application/wasm、font/ttf、font/otf）
   改动 B：新增 Flutter 静态缓存与 SPA location 段
            = /index.html、/main.dart.js、/flutter_bootstrap.js、/flutter_service_worker.js、
              /manifest.json、/version.json、~ ^/assets/(FontManifest|AssetManifest)  -> expires -1
            ^~ /canvaskit/  -> types application/wasm wasm; expires 7d
            ~* ^/assets/.*\.(png|jpe?g|webp|gif|svg|woff2?|ttf|otf)$ -> expires 30d
            /icons/ 与 = /favicon.png -> expires 30d
            location / { try_files $uri $uri/ /index.html; }
   改动 C：末尾旧缓存规则替换（旧写法 `~ .*\.(js|css)?$` 的 ? 使扩展名可选、
            会匹配所有 URI，等于全站 12h，已修正）+ 新增字体缓存规则
   未改动：listen / server_name / SSL 证书路径 / 证书申请 include / HTTP 跳 HTTPS /
           access_log / error_log / 敏感文件与敏感目录拦截 / enable-php-82.conf

2) nginx/proxy/chimu-claw.xyz/trashapi.conf
   -> /www/server/panel/vhost/nginx/proxy/chimu-claw.xyz/trashapi.conf
   改动：仅在原 location ^~ /trashapi 内增补 4 行
         proxy_buffering off; proxy_read_timeout 300s;
         proxy_send_timeout 300s; client_max_body_size 30m;
   未改动：proxy_pass http://127.0.0.1:10003（不带尾斜杠，后端自行剥 /trashapi 前缀）；
           未新建第二个 location

3) backup/
   chimu-claw.xyz.conf.bak.2026-10-24-190644
   trashapi.conf.bak.2026-10-24-190644
   -> 修改前的原始版本，供本地 diff / 回滚

二、未包含的文件（有意排除）
-----------------------------------------
/www/wwwroot/trash/config.local.json
  该文件本次只新增了一个键 GLM_API_KEY，但内含明文 API Key，未打进压缩包。
  若需同步，请手工处理（不要提交进 Git 仓库）：
      "GLM_API_KEY": "<在此填你的密钥>"
  权限建议：chown www:www、chmod 640

三、回滚方式
-----------------------------------------
cp backup/chimu-claw.xyz.conf.bak.2026-10-24-190644 \
   /www/server/panel/vhost/nginx/chimu-claw.xyz.conf
cp backup/trashapi.conf.bak.2026-10-24-190644 \
   /www/server/panel/vhost/nginx/proxy/chimu-claw.xyz/trashapi.conf
nginx -t && nginx -s reload

四、同步到本地后注意
-----------------------------------------
- 面板会重写 vhost/*.conf 中的部分自动管理段，本地改动若要与面板共存，
  建议只同步 location 段与 gzip 段，避免与面板生成的段冲突。
- 本机 nginx 需编译 with-http_gzip_static_module，否则 `gzip_static on;` 会报
  "unknown directive"。检查：nginx -V 2>&1 | grep -o with-http_gzip_static_module
