# Theme Engine

Codex core and custom module developers should use the Theme Engine to ensure that their UI is consistently styled and colored in a way that aligns with the user's preferences.

Module developers can also create their own custom themes and color schemes.

**IMPORTANT:** Please do not try to create custom themes or color schemes yet. We're still early days. Things *will* change and those changes *will break your work*.
We understand that lots of folks will be eager to create their own themes & color schemes. We are, too! We'll let you know as soon as it's safe to do this!

## Developer Usage

The **best** path to theming your UI is:

1. In your topmost panel / window, use `styles = ThemeEngine.GetStyles()`.
2. In your components, apply appropriate class names from the theme engine to your controls.
3. Never use a constant color for anything; always use a class.
4. Generally use inline properties to control specific layout, etc.

This path ensures that your UI will leverage any theme that the end-user chooses.

Sometimes, you will need to add **custom behaviors** through styles instead of inlining properties or writing event handlers. When you do this:

1. Ensure any colors and font faces you use leverage the `@` tokens in the theme and color scheme dictionary. Never use hardcoded colors.
2. Taking #1 above into account, create your styles block.
3. In your topmost panel / window, use `styles = ThemeEngine.MergeStyles(myCustomStyles)`.

Rarely, you might want to **apply styling to a single control** in a way that might override the styling it inherits from its parent. This is usullay a **Very Bad Idea** so make sure you've exhausted the above options before you try this.

But if you need to do this, follow this path:

1. Ensure any colors and font faces you use leverage the `@` tokens in the theme and color scheme dictionary. Never use hardcoded colors.
2. Taking #1 above into account, create your styles block.
3. In the control in which you want to override styles, use `styles = ThemeEngine.MergeTokens(myCustomStyles)`.

## Deprecated Controls

Please try to avoid using the following controls, using the suggested alternative instead.

| Deprecated Control | Use Instead |
|--|--|
| gui.AddButton | gui.Button{ classes = { addButton }} |
| gui.Border, gui.PrettyBorder | gui.Panel{ classes = { border }} |
| gui.CloseButton | gui.Button{ classes = { closeButton }} |
| gui.CopyButton | gui.Button{ classes = { copyButton }} |
| gui.FancyButton | gui.Button |
| gui.HudIconButton | gui.Button{ classes = { sizeM }, icon = "image" } |
| gui.IconButton | gui.Button{ icon = iconName } |
| gui.PrettyButton | gui.Button |
| gui.SetEditor | gui.Multiselect |
| gui.SettingsButton | gui.Button{ classes = { settingsButton }} |
| gui.SimpleIconButton | gui.Button { icon = iconName } |

## Color Scheme

Color schemes are intentionally simple to ensure consistency and relationship between colors in the UI.

Please review the `default` color scheme in `DMHub Core UI / DefaultStyles.lua` to see the available colors and gradients.

Note that for custom development, you need only specify differences from `default` in your color scheme. If you do not include one of the values from default, the Theme Engine will use the value from default for you.

## Theme (incl. Font Faces)

Themes are relatively broad in scope. They consist of fonts and styles. They have four named font use cases and numerous styles.

Please review the `default` theme in `DMHub Core UI / DefaultStyles.lua` to see the available fonts and class selectors.

When creating cutom schemes, remember that, like Color Schemes, the Theme Engine will use the default entries if your theme excludes them.

The styles are built to be composable, so if you want a large, bold label you could use `gui.Label{ classes = {"sizeL", "bold"}, ...}`.

Interesting classes:

| Class / Selector | Applies To | When To Use |
|--|--|--
|bordered|Everything?|When you want a border around your control.|
|image|panel|Ensure the bgcolor is white so the image shows properly.|
|portraitImage|panel|Opinionated about sizing for portraits.|
|sizeXs, sizeS, sizeM,<br>sizeL, sizeXl, sizeXxl|label, button|Default sizing.|
|bold, noBold|anything|Make text bold or not bold.|
|number|label|The label holds only a number.|
|disabled|button, checkbox, input|Appear disabled.|
|flipped|button w/ icon|Flips the icon horizontally.|
|tabBar, tab|?|Create a tab bar.|
|tableLabel|label|Header label in a table.|
|row|panel|Row in a table.|
|row, headerRow|panel|Header row in a table.|
|row, evenRow - or oddRow|panel|Zebra-stripe a table row.|
|formRow|panel|A row in a form, label left, control right.|
|form|label, input, dropdown, etc.|Apply to items in formRow.|
|formStackedRow|panel|A row in a form, label top, control bottom.|
|formStacked|label, input, dropdown, etc.|Apply to items in formRow.|
|featureCard*|panel,etc|Bordered, collapsible cards like the feature editors in Compendium.|
|dialog|panel|Styling for a panel launched as a dialog.|
|launchablePanel|panel|Style a panel launched as a launchable panel.|
|hidden|any|Hides the control but does not collapse the area it was in.|
|collapsed|any|Hides the control and collapses the area it was in.|
|collapsedAnim|any|As collapsed, but with animation.|
