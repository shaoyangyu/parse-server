
Parse.Cloud.define("hello",(request,response)=>{
    var Post=Parse.Object.extend("Post")
    const query=new Parse.Query("Post");
    query.equalTo("objectId", request.params.name);
    query.first().then((post)=>{
        const comments=post.relation("comments")
        console.log(comments.query().find({
            success: (list)=>{
                console.log(list)
            }
        }));
        response.success(comments);

    })

})

