# App Store Submission Checklist (HuoZheMe)

## 1) Project Settings Already Applied
- Team ID: `U7LKKPP9HU`
- Bundle ID: `com.toutoubaofu.huozheme`
- API base URL (Release): `https://heartbeatapp.space`
- Terms URL: `https://heartbeatapp.space/terms`
- Privacy URL: `https://heartbeatapp.space/privacy`

## 2) Manual Steps in Xcode
1. Open `frontend/HeartbeatApp.xcodeproj`.
2. Select target **HeartbeatApp** -> **Signing & Capabilities**.
3. Confirm Team is your Apple Developer team (`U7LKKPP9HU`).
4. Keep signing as **Automatically manage signing**.
5. Build on a real device (Release) and verify login/check-in/delete-account flow.

## 3) Archive and Upload
1. In Xcode, select **Any iOS Device (arm64)**.
2. Product -> **Archive**.
3. In Organizer, click **Distribute App** -> **App Store Connect** -> **Upload**.

## 4) App Store Connect Required Fields
- Privacy Policy URL: `https://heartbeatapp.space/privacy`
- Terms of Use URL (if used): `https://heartbeatapp.space/terms`
- Category / Age Rating / Copyright
- App screenshots for required iPhone sizes

## 5) Privacy Label Draft (Based on Current Features)
Potentially collected data:
- Contact Info: email
- User Content: emergency contact names and phone numbers
- Identifiers: app account identifier (`userId`)
- Usage Data: check-in status/history

If used for account/auth only and not ad tracking, mark accordingly in App Privacy.

## 6) App Review Notes Template
### Chinese
审核说明：
1. App 为家庭安全打卡应用。
2. 注册登录后可在设置页看到“Delete Account（删除账号）”。
3. 删除路径：Settings -> Danger Zone -> Delete Account -> 输入当前密码确认。
4. 删除后账号数据将从服务器删除并自动退出登录。
5. 隐私政策：`https://heartbeatapp.space/privacy`

### English
Review Notes:
1. This app is a family safety daily check-in app.
2. After sign-in, users can find **Delete Account** in Settings.
3. Deletion path: Settings -> Danger Zone -> Delete Account -> enter current password to confirm.
4. After deletion, account data is removed from server and user is signed out.
5. Privacy Policy: `https://heartbeatapp.space/privacy`
