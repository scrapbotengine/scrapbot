# Asset Import Showcase

This project demonstrates source texture and static glTF imports. Run it with:

```sh
scrapbot run examples/assets
```

The source assets are declared as stable UUID resources. Scrapbot incrementally compiles them into `.scrapbot/imported/`; the scene references the texture through a material and instantiates the glTF through `scrapbot.model`.
