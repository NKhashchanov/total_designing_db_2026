# Git за 5 минут

## Полный цикл сдачи (шпаргалка)

1. **Форк.** Открой репозиторий курса на GitHub или GitVerse. Нажми кнопку «Fork» (вверху справа). Ты попадёшь в свою копию — туда можно пушить.
2. **Клонирование.** Скопируй URL своего форка. В терминале:
   ```bash
   git clone <твой_url>
   cd foodexpress-tz
   ```
3. **Ветка.** Создай рабочую ветку:
   ```bash
   git checkout -b feature/db-<твоя_фамилия>
   ```
4. **Работа.** Создавай файлы в папке `db/`.
5. **Фиксация.** Когда готов кусок:
   ```bash
   git add db/
   git commit -m "FOOD-101: add schema"
   git push -u origin feature/db-<твоя_фамилия>
   ```
6. **Сдача.** Проверь `docs/acceptance.md` и пришли ссылку на форк преподавателю.

## Типовые ошибки

- `Permission denied` — ты клонировал главный репозиторий (upstream), а не свой форк. Проверь URL.
- `fatal: not a git repository` — ты не в папке проекта. Сделай `cd foodexpress-tz`.
- `nothing to commit` — ты забыл `git add` перед `git commit`.
- `src refspec does not match` — не создал ветку `checkout -b` или пушишь не туда.