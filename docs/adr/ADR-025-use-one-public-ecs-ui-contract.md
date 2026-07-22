# ADR-025: Use one public ECS UI contract

**Date:** 2026-07-15

## Context

Scrapbot's editor is the first substantial consumer of the ECS UI, but it is not a separate UI product. The initial editor implementation constructed public UI storage through private helpers, read component fields directly, and dispatched several interactions through editor-only roles inside the shared reconciler. Project Luau and native systems could detect public UI component membership, but their generated payloads were empty and they could not observe the same retained control state.

That split makes the editor a misleading showcase: controls can look reusable while their useful behavior remains available only to engine code. It also duplicates component ownership, mutation, styling, and interaction rules.

## Decision

Treat the public `scrapbot.ui_*` ECS components as the only widget contract for project UI, native extensions, and editor chrome.

- Construct and mutate public UI storage through typed ECS component procedures. Editor composition helpers may arrange widgets, but must delegate public component ownership and string lifetime to those procedures.
- Register the real public fields of every UI component so generated Luau types and queries expose actual layout, value, and style data rather than empty marker payloads.
- Represent pointer and control interaction through the public `scrapbot.ui_state` component. Hover, active, and focus are element-wide state; activation and change revisions let systems observe durable interaction edges without editor roles.
- Keep editor bindings, history, scene selection, transport actions, and inspector validation in editor systems or adapters that consume generic UI state. The renderer may implement widget mechanics, but it must not assign project meaning to a control.
- Derive component inspector panels from live registry membership and runtime inspection of the canonical typed payload. Dynamic project/native components use their registry schema as runtime type metadata. Component-name branches, hand-authored field rows, and per-component panel builders are prohibited; only payload-location, validation, and reusable type/semantic controls may specialize.
- Emit engine-internal generic activation and change events from the shared interaction pass, then let editor orchestration consume that ordered stream. Projects continue to consume the public `ui_state` revisions. Do not branch from reusable control mechanics directly into editor commands.
- Add missing layout or control behavior as reusable components or component fields. Do not repair editor layout with role-specific post-layout mutation when the same need can be expressed generally.
- Model nested browsers through tree-enabled public `ui_list` and semantic tree metadata on direct-child `ui_layout` rows. Shared UI owns flattening, indentation, collapsed-branch filtering, cycle-safe subtree placement, and sibling normalization; editor code only translates the resulting public drop into scene Transform/order history and persistence.
- Compose panel title actions from ordinary child `ui_button` entities with public icon and title-placement fields. Do not add a singular close/remove action payload to `ui_panel` or special-case its hit testing and paint path.
- Define reusable defaults while retaining per-entity style overrides, including explicit corner radius and square corners.
- Treat internal control chrome as part of the same public style contract: scrollbars, disclosure icons, input prefixes/selections/borders/carets, and checkbox boxes/checkmarks may not depend on editor-only constants.

Project files, Luau, native extensions, and editor code may use different authoring syntax, but they must produce and consume the same ECS component data.

## Consequences

The editor becomes a first-party compatibility test for the public UI instead of a privileged implementation. Improvements to panels, lists, tables, scrolling, inputs, styling, and interaction become available to projects without porting editor code.

Public UI schemas and generated bindings become a larger compatibility surface. Adding a widget field requires updating parsing, typed scripting/native access, mutation, tests, and documentation together. Renderer state changes must have deterministic ECS semantics, and transient interaction flags need revision counters so missed frames do not lose the fact that an interaction occurred.

Editor composition code still exists because the editor has a particular information architecture. That code may select entities, create inspector rows, or invoke editor commands, but it must not own a second set of widget primitives. A reusable widget can therefore be composed into editor-specific meaning without acquiring an editor-specific event or rendering path.
