# Настройка автосборки (CI/CD) для KeenRouterManager

## Что уже готово

✅ **GitHub Actions workflows** - автоматическая сборка при push  
✅ **Базовая сборка** (без подписи) - срабатывает сразу  
✅ **Workflow с подписью** - опциональная подписанная сборка  

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

### Вариант 2: С подписью кода (если нужна распространение)

1. **Подготовьте сертификат** (следуйте инструкциям в [../.github/CI-SETUP.md](../.github/CI-SETUP.md))

2. **Добавьте Secrets** в Settings → Secrets and variables → Actions:
   - `APPLE_CERTIFICATE_P12`
   - `APPLE_CERTIFICATE_PASSWORD`
   - `PROVISIONING_PROFILE` (опционально)

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

- **На tags (v1.0.0)** - если включен workflow с подписью:
  - ✅ Подписанная сборка
  - ✅ Подготовка для распространения
  - ✅ Нотаризация (если настроена)

## Просмотр результатов

1. Откройте вкладку **Actions** в GitHub репо
2. Нажмите на последний workflow run
3. Скачайте артефакты (если нужны локально)

## Требования

- **GitHub repository** (требует push доступ)
- **Xcode** не нужен локально для CI - используется GitHub runner
- **Secrets** только если хотите подписанную сборку

## Дополнительно

Подробнее см. в [../.github/CI-SETUP.md](../.github/CI-SETUP.md)
