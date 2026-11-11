// FiveM hosts resource UIs in a parent frame. Embedded custom apps are children.
export function isHostMessage(source: MessageEventSource | null, self: Window, parent: Window): boolean {
  return source === null || source === self || source === parent;
}
