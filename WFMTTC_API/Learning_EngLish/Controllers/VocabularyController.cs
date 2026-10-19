using Learning_EngLish.Data;
using Learning_EngLish.DTOs;
using Learning_EngLish.Repositories;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace Learning_EngLish.Controllers;

[ApiController]
[Route("api/[controller]")]
public class VocabularyController : ControllerBase
{
    private readonly VocabularyRepository _repository;

    public VocabularyController(VocabularyRepository repository)
    {
        _repository = repository;
    }

    // GET: api/Vocabulary?topicId=1&wordTypeId=2&search=app
    [HttpGet]
    public async Task<ActionResult<List<VocabularyResponse>>> GetAll(
        [FromQuery] int? topicId,
        [FromQuery] int? wordTypeId,
        [FromQuery] string? search)
    {
        return await _repository.GetAllAsync(topicId, wordTypeId, search);
    }

    // GET: api/Vocabulary/5
    [HttpGet("{id:int}")]
    public async Task<ActionResult<VocabularyResponse>> GetById(int id)
    {
        var vocabulary = await _repository.GetByIdAsync(id);
        return vocabulary == null ? NotFound() : vocabulary;
    }

    // POST: api/Vocabulary
    [HttpPost]
    public async Task<ActionResult<VocabularyResponse>> Create(VocabularyRequest request)
    {
        try
        {
            var id = await _repository.CreateAsync(request);
            var created = await _repository.GetByIdAsync(id);
            return CreatedAtAction(nameof(GetById), new { id }, created);
        }
        catch (SqlException ex) when (ex.Number == SqlErrors.ForeignKeyViolation)
        {
            return BadRequest("TopicId or WordTypeId does not exist.");
        }
        catch (SqlException ex) when (SqlErrors.IsDuplicate(ex.Number))
        {
            return Conflict($"'{request.Word}' already exists with this word type.");
        }
    }

    // PUT: api/Vocabulary/5
    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, VocabularyRequest request)
    {
        try
        {
            var updated = await _repository.UpdateAsync(id, request);
            return updated ? NoContent() : NotFound();
        }
        catch (SqlException ex) when (ex.Number == SqlErrors.ForeignKeyViolation)
        {
            return BadRequest("TopicId or WordTypeId does not exist.");
        }
        catch (SqlException ex) when (SqlErrors.IsDuplicate(ex.Number))
        {
            return Conflict($"'{request.Word}' already exists with this word type.");
        }
    }

    // DELETE: api/Vocabulary/5
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
            return Conflict("This word is used in a quiz. Remove it from the quiz first.");
        }
    }
}
