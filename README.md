```
helm install vault --atomic ./vault --dependency-update -f ./vault/values.yaml
```

```
k apply -f secretstore.yaml   
```

```
k apply -f externalsecret.yaml
```