```
podman pull registry.access.redhat.com/ubi8/go-toolset    
```
```
git clone git@github.com:containercraft/p1-gotools.git && cd p1-gotools    
```
```
podman run -d --volume $(pwd):/opt/app-root/src/p1-gotools --name p1dev registry.access.redhat.com/ubi8/go-toolset bash    
```
```
podman run -d --volume $(pwd):/opt/app-root/src:z --name p1dev registry.access.redhat.com/ubi8/go-toolset bash    
```
```
podman exec -it p1dev bash
>>>>>>> go-dev
```
