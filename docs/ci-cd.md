# Настройка автосборки (CI/CD) для KeenRouterManager

## Что уже готово

✅ **GitHub Actions workflows** - автоматическая сборка при push  
✅ **Базовая сборка** (без подписи) - срабатывает сразу  
✅ **Workflow с подписью** - опциональная подписанная сборка  
✅ **Релизный workflow** - собирает `.app.zip` и `.dmg` и публикует их в GitHub Releases  

## Как включить

### Вариант 1: Только сборка (рекомендуется для начала)

Просто закоммитьте файлы `.github/workflows/build.yml`:

```bash
git add .github/
git commit -m "Add GitHub Actions CI/CD workflow"
git push
```

Этого достаточно! Сборка будет автоматически запускаться при push в `main` и `develop`.

**Ждите результатов:** перейдите в **Actions** на странице репо.

### Вариант 1.1: Автоматический релиз без подписи

Если вы хотите публиковать готовую программу в GitHub Releases без подписи кода:

1. Убедитесь, что в репозитории включено `Settings -> Actions -> General -> Workflow permissions -> Read and write permissions`
2. Создайте тег версии, например:

```bash
git tag -a v0.9.0 -m "Release version 0.9.0"
git push origin v0.9.0
```

После этого workflow `.github/workflows/release.yml`:

- соберет приложение без code signing
- создаст `KeenRouterManager.app.zip`
- создаст `KeenRouterManager.dmg`
- создаст GitHub Release и прикрепит оба файла

### Вариант 2: С подписью кода (если нужна распространение)

1. **Подготовьте сертификат разработчика**

#### Экспорт сертификата из Keychain:

```bash
security find-identity -v -p codesigning
```

Экспортируйте сертификат и приватный ключ в `.p12`, затем закодируйте в base64:

```bash
base64 -i cert.p12 -o cert.p12.base64
base64 -i provisioning-profile.mobileprovision -o provisioning-profile.base64
```

2. **Добавьте Secrets** в Settings → Secrets and variables → Actions:
   - `APPLE_CERTIFICATE_P12`
   - `APPLE_CERTIFICATE_PASSWORD`
   - `PROVISIONING_PROFILE` (опционально)
  - `APPSTORE_API_KEY` (опционально)

3. **Обновите ExportOptions.plist** с вашим Team ID

4. **Закоммитьте все файлы:**
   ```bash
   git add .github/ ExportOptions.plist
   git commit -m "Add signed build workflow"
   git push origin main
   ```

## Что произойдет автоматически

- **На каждый push в main/develop:**
  - ✅ Будет собран проект
  - ✅ Создан .app файл
  - ✅ Загружены артефакты (доступны 7 дней)

- **На tags (v1.0.0)**:
  - ✅ Будет собран неподписанный релиз
  - ✅ Будут созданы `.app.zip` и `.dmg`
  - ✅ Будет создан GitHub Release

- **При ручном запуске `build-signed.yml`**:
  - ✅ Подписанная сборка
  - ✅ Подготовка для распространения
  - ✅ Нотаризация (если настроена)

## Просмотр результатов

1. Откройте вкладку **Actions** в GitHub репо
2. Нажмите на последний workflow run
3. Для обычных CI-сборок скачайте артефакты из Actions
4. Для релизов откройте вкладку **Releases** и скачайте `.dmg` или `.app.zip`

## Требования

- **GitHub repository** (требует push доступ)
- **Xcode** не нужен локально для CI - используется GitHub runner
- **Secrets** только если хотите подписанную сборку

## Актуальные workflow

### `build.yml`

- запускается на push в `main` и `develop`
- запускается на pull request в `main` и `develop`
- выполняет неподписанную release-сборку

### `release.yml`

- запускается на тегах `v*`
- публикует неподписанный релиз в GitHub Releases
- требует `contents: write` permission для `GITHUB_TOKEN`

### `build-signed.yml`

- запускается вручную
- использует `ExportOptions.plist`
- нужен только если вы настраиваете подписанную сборку

## Troubleshooting

### Ошибка: `Resource not accessible by integration`

Проверьте, что в репозитории включено:

- `Settings -> Actions -> General -> Workflow permissions -> Read and write permissions`

### Ошибка: `xcodebuild: command not found`

Это означает, что локально выбраны только Command Line Tools. Для этого проекта нужна полная установка Xcode.

### Ошибка подписи

Проверьте:

- что secrets корректно закодированы в base64
- что `teamID` в `ExportOptions.plist` совпадает с Apple Developer Team
- что сертификат содержит приватный ключ

## Дополнительно

Если signed build вам пока не нужен, для обычной работы достаточно `build.yml` и `release.yml`.
