---
tags:
  - react
  - performance
  - frontend
  - context
created: 2026-06-08
source: https://www.developerway.com/posts/react-re-renders-guide
---

# Preventing Context-Caused Re-renders

> Part 6 of [[React Re-renders Guide]]

---

## The Problem

Every component that calls `useContext` **re-renders when the context value changes** — even if that component only uses a small portion of the data that didn't change.

> Direct memoization of consumers does not work for context changes.

---

## Pattern 1: Memoize the Provider Value

If the Context Provider sits inside a component that might re-render, memoize the value to prevent cascading subscriber updates.

```jsx
// ❌ BAD — new object reference on every ParentComponent render
const ParentComponent = () => {
  const [state, setState] = useState({});
  return (
    <AppContext.Provider value={{ state, setState }}>
      <Children />
    </AppContext.Provider>
  );
};

// ✅ GOOD — memoize the context value
const ParentComponent = () => {
  const [state, setState] = useState({});
  const value = useMemo(() => ({ state, setState }), [state]);
  return (
    <AppContext.Provider value={value}>
      <Children />
    </AppContext.Provider>
  );
};
```

---

## Pattern 2: Split Data and API Contexts

Separate the context into two providers:
- **Data context** — the actual state values
- **API context** — setter functions / handlers (stable references)

Components that only dispatch actions (don't read data) subscribe only to the API context and **never re-render on data changes**.

```jsx
const DataContext = createContext(null);
const ApiContext = createContext(null);

const AppProvider = ({ children }) => {
  const [data, setData] = useState(initialData);
  const api = useMemo(() => ({ setData }), []);   // stable reference

  return (
    <ApiContext.Provider value={api}>
      <DataContext.Provider value={data}>
        {children}
      </DataContext.Provider>
    </ApiContext.Provider>
  );
};

// This component never re-renders when data changes
const ActionButton = () => {
  const { setData } = useContext(ApiContext);
  return <button onClick={() => setData(newData)}>Update</button>;
};
```

---

## Pattern 3: Split Data Into Chunks

For large contexts managing multiple independent data slices, create **separate providers per slice**. Consumers only re-render when their specific slice changes.

```jsx
// Instead of one big context:
// <AppContext.Provider value={{ user, theme, notifications }}>

// Split into independent contexts:
<UserContext.Provider value={user}>
  <ThemeContext.Provider value={theme}>
    <NotificationsContext.Provider value={notifications}>
      {children}
    </NotificationsContext.Provider>
  </ThemeContext.Provider>
</UserContext.Provider>
```

---

## Pattern 4: Context Selectors (Higher-Order Component + memo)

There is no native selector API in React context. Workaround: use a HOC that subscribes to the full context but passes only the selected slice to a memoized component.

```jsx
// The memoized component only re-renders if its specific slice changed
const withUserName = (Component) => {
  const MemoComponent = React.memo(Component);
  return () => {
    const { userName } = useContext(AppContext);
    return <MemoComponent userName={userName} />;
  };
};

const UserGreeting = withUserName(({ userName }) => <h1>Hello {userName}</h1>);
```

> This works because `React.memo` on the inner component prevents re-renders when the passed prop (`userName`) hasn't changed — even though the HOC itself re-renders on every context change.

---

## Summary

| Strategy | Prevents re-renders for... |
|----------|---------------------------|
| **Memoize provider value** | All consumers (when parent re-renders) |
| **Split Data / API** | Action-only components |
| **Split into chunks** | Components using only one data slice |
| **HOC + memo selector** | Components using one field from a large context |

---

## Related

- [[React Re-renders - Why Components Re-render]] — context is trigger #3
- [[React Re-renders - useMemo and useCallback]] — used in pattern 1 & 2
