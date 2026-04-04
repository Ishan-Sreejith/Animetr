Welcome! This is a template for developing a 1.21.5 Minecraft shader with Iris. All shader files are in the `shaders` folder. They currently don't do anything special.

From the terminal, you can run:
- `gradlew runShaderClient` to launch the client with Iris with your shaderpack automatically applied
- `gradlew assemble` to put all shaderpack files into a ready ZIP file. You'll find your shader under [./build/releases](./build/releases)!

## What now?
Take a look at some guides! We recommend the [Hack Club Lumen guides](https://lumen.hackcraft.hackclub.com/guides) and the official [Iris tutorials](https://shaders.properties/current/guides/your-first-shaderpack/0_intro/).

After you're done developing your shader, we recommend publishing it to [Modrinth](https://modrinth.com). You can also submit it to [Hack Club Lumen](https://lumen.hackcraft.hackclub.com) to get free Minecraft _or_ get your hands on a shiny new GPU!

## Notes

The Gradle files are completely optional, and exist to help you debug your shader. You can delete them if you want. This template is based on the [official ShaderLABS template](https://github.com/shaderLABS/Base-330).
