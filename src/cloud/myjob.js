Parse.Cloud.job("myjob",(request,status)=>{
    status.message("I am just stared")
    var longrun=new Promise((ok,failed)=>{
        setTimeout(()=>{console.log("done")},5000)
        ok()
    })
    
    longrun.then(()=>{status.success("I am done")})
})
