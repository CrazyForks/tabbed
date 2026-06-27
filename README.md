### windows are better 
# tabbed

https://github.com/user-attachments/assets/8b628294-754c-44bd-9088-425cc25b8098

```sh
brew trust --cask zimengxiong/tools/tabbed
brew tap ZimengXiong/tools
brew install --cask tabbed
xattr -dr com.apple.quarantine /Applications/Tabbed.app
```
on first launch, grant **System Settings -> Privacy & Security -> Accessibility**

hold ⌘ while dragging windows to create tab groups

use kb shortcuts alt+1...n to switch between tabs, and alt+tab to cycle between tabs. configure other bindings in ~/.config/tabbed.toml. a config is created for you on first launch
