# GitHub Actions Setup для KeenRouterManager

## Быстрый старт

Базовая сборка (без подписи) автоматически запускается при push в `main` и `develop` ветки. Просто закоммитьте `.github/workflows/build.yml` и все готово!

## Для сборки с подписью кода (опционально)

Если вам нужна подпись кода для распространения через App Store или для нотаризации, следуйте этим шагам:

### 1. Подготовка сертификатов

#### Экспортируем сертификат разработчика:

```bash
# На локальной машине с Keychain
# Откройте Keychain Access → найдите свой сертификат → экспортируйте как .p12
# Или используйте команду:
security find-identity -v -p codesigning

# Экспортируем сертификат и ключ:
security export-cert -t certs -f pemder -P "" -o cert.cer <cert-id>
security export-cert -t privkeys -f pkcs12 -P "" -o cert.p12 <key-id>
```

#### Кодируем в base64:

```bash
base64 -i cert.p12 -o cert.p12.base64
base64 -i provisioning-profile.mobileprovision -o provisioning-profile.base64
```

### 2. Добавляем Secrets в GitHub

Перейдите в **Settings → Secrets and variables → Actions** и добавьте:

- `APPLE_CERTIFICATE_P12` - base64-кодированный .p12 файл
- `APPLE_CERTIFICATE_PASSWORD` - пароль от .p12 файла
- `PROVISIONING_PROFILE` - base64-кодированный provisioning profile
- `APPSTORE_API_KEY` - API key для App Store Connect (опционально)

### 3. ExportOptions.plist

Если используете подписанную сборку, добавьте `ExportOptions.plist` в корень проекта:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

## Workflows

### `build.yml` - Базовая сборка
- ✅ Для pull requests
- ✅ Для commits в main/develop
- ✅ Без подписи кода
- ✅ Загружает артефакты в Actions

### `build-signed.yml` - Подписанная сборка
- ✅ Для tags (v*)
- ✅ Требует Secrets
- ✅ Подписывает код
- ✅ Экспортирует для распространения
- ✅ Нотаризует приложение (если настроено)

## Зависимости и требования

- **macOS runner** (`macos-latest`) - требует полную установку Xcode
- **Xcode** - по умолчанию используется последняя версия на runner
- **Deployment target** - macOS 15.6+ (как указано в Info.plist)

## Troubleshooting

### Ошибка: `xcodebuild: command not found`
→ используется macOS runner без полного Xcode - это нормально для этого проекта

### Ошибка при подписи
→ Проверьте что Secrets правильно закодированы в base64
→ Проверьте что team ID верный в ExportOptions.plist

### Ошибка: `Signing certificate not found`
→ Регенерируйте сертификат и provisioning profile в Apple Developer Account
→ Переэкспортируйте в base64

## Советы

1. Для локальной разработки не требуется ничего - просто открывайте `.xcodeproj` в Xcode
2. GitHub Actions автоматически выбирает macOS с последней Xcode
3. Сборка занимает ~15-20 минут на GitHub runner
4. Артефакты доступны для скачивания через Actions вкладку
