# Plugins and interoperability

## After Effects plugins: not possible

Desktop After Effects plugins are native binaries built for Adobe's desktop SDK on macOS or Windows. They cannot be loaded by an iOS app. iOS also restricts downloading and running new native code in apps (App Store Review Guideline 2.5.2; the current wording has not been re-checked). Motion Studio will not contain a plugin installer that suggests otherwise.

## After Effects projects (.aep): not implemented

The format is proprietary. Whether a reliable and lawful import route exists has not been investigated. No import exists, and no compatibility is claimed.

## What is planned instead

1. **Presets**: effect settings, effect stacks, animation easing and text styles saved as documented data files with a version number and validation. Allowed on iOS because they are data.
2. **Built-in effects**: the 167-name catalogue, implemented natively and independently. Not copies of any third-party effect.
3. **Declarative user effects**: a graph made of built-in operations, stored as data.
4. **Expressions**: a small documented language interpreted by the app. It will not be compatible with all After Effects expressions.
5. **Open-source effects** compiled into the app through reviewed contributions.

Anything that downloads and runs native or GPU code at runtime should be treated as unavailable until proven allowed.

## Interchange formats

PNG and JPEG, supported video and audio, SVG and project packages are planned. None is implemented yet.
