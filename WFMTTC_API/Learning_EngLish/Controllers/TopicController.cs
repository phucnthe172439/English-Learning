using Learning_EngLish.Data;
using Learning_EngLish.DTOs;
using Learning_EngLish.Repositories;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace Learning_EngLish.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TopicController : ControllerBase
{
    private readonly TopicRepository _repository;

    public TopicController(TopicRepository repository)
    {
        _repository = repository;
    }

    // GET: api/Topic
    [HttpGet]
    public async Task<ActionResult<List<TopicResponse>>> GetAll()
    {
        return await _repository.GetAllAsync();
    }

    // GET: api/Topic/5
    [HttpGet("{id:int}")]
    public async Task<ActionResult<TopicResponse>> GetById(int id)
    {
        var topic = await _repository.GetByIdAsync(id);
        return topic == null ? NotFound() : topic;
    }

    // POST: api/Topic
    [HttpPost]
    public async Task<ActionResult<TopicResponse>> Create(TopicRequest request)
    {
        try
        {
            var id = await _repository.CreateAsync(request);
            var created = await _repository.GetByIdAsync(id);
            return CreatedAtAction(nameof(GetById), new { id }, created);
        }
        catch (SqlException ex) when (SqlErrors.IsDuplicate(ex.Number))
        {
            return Conflict($"Topic '{request.Name}' already exists.");
        }
    }

    // PUT: api/Topic/5
    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, TopicRequest request)
    {
        try
        {
            var updated = await _repository.UpdateAsync(id, request);
            return updated ? NoContent() : NotFound();
        }
        catch (SqlException ex) when (SqlErrors.IsDuplicate(ex.Number))
        {
            return Conflict($"Topic '{request.Name}' already exists.");
        }
    }

    // DELETE: api/Topic/5
    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        try
        {
            var deleted = await _repository.DeleteAsync(id);
            return deleted ? NoContent() : NotFound();
        }
        catch (SqlException ex) when (ex.Number == SqlErrors.ForeignKeyViolation)
        {
            return Conflict("This topic still has words or quizzes. Delete or move them first.");
        }
    }
}
