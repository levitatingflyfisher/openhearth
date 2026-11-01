# Web builds: the app's own address and the move page

Peckish on the web lives at its own address, `peckish.familyflourishing.org`
(owner ruling, 15 Nov 2026). `web/CNAME` names it, and the build copies it to
the site root. Two web builds come from the same code:

```sh
# The app at its own address
flutter build web --release --base-href /

# The move page, at levitatingflyfisher.github.io/move/peckish/
flutter build web --release --base-href /move/peckish/ --dart-define=OH_MOVE_PAGE=true
```

The move page stays up for good, because data saved at the old address can
only be read there. It opens straight to the move screen, counts the
records, saves the app's own backup file and writes nothing at start
(`lib/features/move/move_page.dart`). It goes in the landing repo under
`move/peckish/`, without the `CNAME` file.
