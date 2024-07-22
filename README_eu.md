<!--
Ohart ongi: README hau automatikoki sortu da <https://github.com/YunoHost/apps/tree/master/tools/readme_generator>ri esker
EZ editatu eskuz.
-->

# SearXNG YunoHost-erako

[![Integrazio maila](https://dash.yunohost.org/integration/searxng.svg)](https://ci-apps.yunohost.org/ci/apps/searxng/) ![Funtzionamendu egoera](https://ci-apps.yunohost.org/ci/badges/searxng.status.svg) ![Mantentze egoera](https://ci-apps.yunohost.org/ci/badges/searxng.maintain.svg)

[![Instalatu SearXNG YunoHost-ekin](https://install-app.yunohost.org/install-with-yunohost.svg)](https://install-app.yunohost.org/?app=searxng)

*[Irakurri README hau beste hizkuntzatan.](./ALL_README.md)*

> *Pakete honek SearXNG YunoHost zerbitzari batean azkar eta zailtasunik gabe instalatzea ahalbidetzen dizu.*  
> *YunoHost ez baduzu, kontsultatu [gida](https://yunohost.org/install) nola instalatu ikasteko.*

## Aurreikuspena

SearxXNG is a free internet metasearch engine which aggregates results from more than 70 search services. Users are neither tracked nor profiled.


**Paketatutako bertsioa:** 2024.07.08~ynh3

**Demoa:** <https://searx.be>

## Pantaila-argazkiak

![SearXNG(r)en pantaila-argazkia](./doc/screenshots/screenshot_1.png)

## Dokumentazioa eta baliabideak

- Aplikazioaren webgune ofiziala: <https://docs.searxng.org>
- Erabiltzaileen dokumentazio ofiziala: <https://docs.searxng.org/user/>
- Administratzaileen dokumentazio ofiziala: <https://docs.searxng.org/admin/>
- Jatorrizko aplikazioaren kode-gordailua: <https://github.com/searxng/searxng>
- YunoHost Denda: <https://apps.yunohost.org/app/searxng>
- Eman errore baten berri: <https://github.com/YunoHost-Apps/searxng_ynh/issues>

## Garatzaileentzako informazioa

Bidali `pull request`a [`testing` abarrera](https://github.com/YunoHost-Apps/searxng_ynh/tree/testing).

`testing` abarra probatzeko, ondorengoa egin:

```bash
sudo yunohost app install https://github.com/YunoHost-Apps/searxng_ynh/tree/testing --debug
edo
sudo yunohost app upgrade searxng -u https://github.com/YunoHost-Apps/searxng_ynh/tree/testing --debug
```

**Informazio gehiago aplikazioaren paketatzeari buruz:** <https://yunohost.org/packaging_apps>
