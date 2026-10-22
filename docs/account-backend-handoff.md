# Horizon iOS 账号与后端交接

更新日期：2026-10-08。用户要求 iOS App 同时支持邮箱密码与 Sign in with Apple，已确认有现成 Xcode 项目和正式 Apple Developer Program 会员。后端本地基础已完成，下一步是在 Horizon 中接入账号界面与真实 Apple 授权，御坂说明道。

## 项目位置与配置

- iOS 项目：`/Users/wukaihan/Documents/Coding/Xcode/Apps/Clash`。打开 `Horizon.xcodeproj`，使用 `Horizon` scheme；不要误用同目录的旧 `Clash.xcodeproj`。
- 当前主 App Bundle ID：`Kenote.Clash`；工程配置的 Team ID：`68WND8JR7P`。沿用现有身份，实际 Apple 后台配置仍需用户确认。
- 后端：`/Users/wukaihan/Documents/Coding/VSCode/Websites/Personal WebPage`。
- 后端详细接口与配置：[README](</Users/wukaihan/Documents/Coding/VSCode/Websites/Personal WebPage/README.md:126>)。
- 待加入 iOS 主 target 的客户端：[AccountClient.swift](</Users/wukaihan/Documents/Coding/VSCode/Websites/Personal WebPage/integrations/ios/AccountClient.swift>)。

## 已完成与验证范围

- 个人主页、独立项目示例与账号服务分别使用 3000、3001、3002 端口。主页保持黑白、少英文、持续动态的玻璃质感 3D 双环；不需要为账号接入重新设计主页。
- `apps/accounts/service.mjs` 使用 Better Auth 1.7.7 与 SQLite，实现邮箱注册与验证、登录、资料修改、密码修改与找回、多设备会话撤销、退出和账号删除。
- `apps/accounts/apple.mjs` 实现原生 Apple token 验签、Bundle ID 与单次 nonce 校验、授权码交换；加密保存 refresh token，删除账号时先撤销 Apple 授权。
- Swift 客户端使用 URLSession 与 Keychain。项目 API 可通过 `shared/account-session.mjs` 核验账号身份，再检查自己的业务数据所有权。
- 上一轮 15 项自动化测试通过，包含账号隔离、会话失效、密码重置、删除和 Apple 流程。Apple 使用本地签名与模拟 HTTP；Swift 通过 iOS Simulator SDK 类型检查，**尚未完成实际 App 构建接入、Keychain 实机测试或真实 Apple 登录**。

本次交接检查：后端尚无 `.env`；Horizon 主 App entitlements 尚无 Sign in with Apple，本地 HTTP 调试配置尚未添加，未找到账号相关 Swift 文件。当前没有发现 3002 端口监听，后续对话需重新确认运行状态，御坂补充道。

## 下一步操作

1. **先检查当前工作区。** iOS 仓库有大量既存未提交改动；保留全部改动，不重置、不覆盖。读取当前 `AGENTS.md`，核对主 App、设置页与状态协调方式。
2. **启动后端并跑通邮箱账号。** 在后端目录执行 `npm run dev:accounts`；检查 `http://127.0.0.1:3002/api/health`。本地验证与重置邮件位于 `data/accounts/outbox/*.json`，打开对应 `url` 完成操作；目前不投递真实邮件。回归命令为 `npm run check`。
3. **由用户完成 Apple 后台配置。** 为 `Kenote.Clash` 开启 Sign in with Apple，配置 Primary App ID，创建关联私钥，下载 `.p8`，确认 Team ID 与 Key ID。在后端 `.env` 填写 `APPLE_BUNDLE_ID`、`APPLE_TEAM_ID`、`APPLE_KEY_ID`、`APPLE_PRIVATE_KEY_PATH`；参考 `.env.example`，不要覆盖已有配置。重启后 `apple: true` 仅表示配置加载成功。
4. **接入 Horizon 服务层和页面。** 将客户端放入 `Horizon/Services/`，添加账号状态协调、会话恢复和错误处理；账号主页面及独立 sheet 各自成文件，按 `Horizon/Features/Account/` 组织。先明确账号入口位置、是否必须登录，以及账号删除对本机订阅的影响；不擅自让现有 VPN 功能依赖登录，也不把订阅上传到后端。
5. **配置并联调 iOS。** 给主 App target 添加 Sign in with Apple capability；仅在 DEBUG 中配置本地 HTTP，客户端地址使用 `http://127.0.0.1:3002`。Apple 请求先调用 `prepareAppleRequest()`，保留 nonce，完成系统授权后调用 `signInWithApple(credential:nonce:)`。nonce 原样使用，不再次哈希。先使用 Simulator；真机的回环地址不是 Mac，真机联网方案需另外安排。
6. **完成验收。** 构建实际 Horizon target，测试注册验证、邮箱及 Apple 首次与再次登录、重启恢复、退出、多设备撤销、密码重置和账号删除；确认原有隧道与订阅行为不受影响。真机动效观感由用户反馈，构建通过不算视觉验收。

## 尚未完成与边界

- 邮箱与 Apple 账号不自动合并，尚未实现主动绑定与解绑；当前 Apple 配置只支持一个 Bundle ID。若要跨多个 App 共用身份，需要另行明确范围与权限。
- 当前账号服务只允许本地回环监听，并拒绝生产模式。域名与部署平台尚未选择，未部署云服务。上线还需要 HTTPS、真实发信、生产数据库与密钥管理、备份、监控和业务数据删除流程。
- `.p8` 与后端密钥只保存在本机或服务端，不加入 App、不提交 Git、不粘贴到聊天。`data/accounts/` 已被忽略，已有数据库与密钥必须保留。
- SGT Voting 是帮助他人的项目，不属于个人项目架构，不接入或修改它。
- 本轮仅新增交接文档，未修改 Horizon 代码、签名配置、后端实现，也未发送消息到其他对话；下一对话从真实 App 接入开始，御坂说明道。
