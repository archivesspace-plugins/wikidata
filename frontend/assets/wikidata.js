$(function () {
  var $searchForm = $('#wikidata_search');
  var $importForm = $('#wikidata_import');

  var $results = $('#results');
  var $selected = $('#selected');

  var selected_qids = {};

  var renderResults = function (json) {
    decorateResults(json);

    $results.empty();
    $results.append(AS.renderTemplate('template_wikidata_result_summary', json));
    $.each(json.records, function (i, record) {
      var $result = $(
        AS.renderTemplate('template_wikidata_result', {
          record: record,
          selected: selected_qids
        })
      );
      if (selected_qids[record.qid]) {
        $('.alert-success', $result).removeClass('d-none');
      } else {
        $('button', $result).removeClass('d-none');
      }
      $results.append($result);
    });
    $results.append(AS.renderTemplate('template_wikidata_pagination', json));
  };

  var decorateResults = function (resultsJson) {
    if (typeof resultsJson.query === 'string') {
      resultsJson.queryString =
        '?q=' + encodeURIComponent(resultsJson.query) +
        '&records_per_page=' + (resultsJson.records_per_page || 10);
    }
  };

  var selectedQids = function () {
    var result = [];
    $('[data-qid]', $selected).each(function () {
      result.push($(this).data('qid'));
    });
    return result;
  };

  var removeSelected = function (qid) {
    selected_qids[qid] = false;
    $("[data-qid='" + qid + "']", $selected).remove();
    var $resultSelectRecordBtn = $("[data-qid='" + qid + "']", $results);
    if ($resultSelectRecordBtn.length > 0) {
      const $result = $resultSelectRecordBtn.closest('.wikidata-result');
      $result.removeClass('selected');
    }

    if (selectedQids().length === 0) {
      $selected.siblings('.alert-info').removeClass('d-none');
      $('#import-selected').attr('disabled', 'disabled');
    }
  };

  var addSelected = function (qid, $result) {
    selected_qids[qid] = true;
    $selected.append(
      AS.renderTemplate('template_wikidata_selected', { qid: qid })
    );

    $result.addClass('selected');

    $selected.siblings('.alert-info').addClass('d-none');
    $('#import-selected').removeAttr('disabled', 'disabled');
  };

  var resizeSelectedBox = function () {
    $selected
      .closest('.selected-container')
      .width($selected.closest('.col-md-4').width() - 30);
  };

  $searchForm.ajaxForm({
    dataType: 'json',
    type: 'GET',
    beforeSubmit: function () {
      if (!$('#wikidata-search-query', $searchForm).val()) {
        return false;
      }

      $('.btn', $searchForm)
        .attr('disabled', 'disabled')
        .addClass('disabled')
        .addClass('busy');
    },
    success: function (json) {
      $('.btn', $searchForm)
        .removeAttr('disabled')
        .removeClass('disabled')
        .removeClass('busy');
      renderResults(json);
    },
    error: function (err) {
      $('.btn', $searchForm)
        .removeAttr('disabled')
        .removeClass('disabled')
        .removeClass('busy');
      AS.openQuickModal(
        AS.renderTemplate('template_wikidata_search_error_title'),
        AS.renderTemplate('template_wikidata_search_error_message')
      );
    }
  });

  $importForm.ajaxForm({
    dataType: 'json',
    type: 'POST',
    beforeSubmit: function () {
      $('#import-selected')
        .attr('disabled', 'disabled')
        .addClass('disabled')
        .addClass('busy');
    },
    success: function (json) {
      $('#import-selected').removeClass('busy');
      if (json.job_uri) {
        AS.openQuickModal(
          AS.renderTemplate('template_wikidata_import_success_title'),
          AS.renderTemplate('template_wikidata_import_success_message')
        );
        setTimeout(function () {
          window.location = json.job_uri;
        }, 2000);
      } else if (json.error) {
        $('#import-selected').removeAttr('disabled').removeClass('busy');
        AS.openQuickModal(
          AS.renderTemplate('template_wikidata_import_error_title'),
          json.error
        );
      }
    },
    error: function (err) {
      $('.btn', $importForm)
        .removeAttr('disabled')
        .removeClass('disabled')
        .removeClass('busy');
      AS.openQuickModal(
        AS.renderTemplate('template_wikidata_import_error_title'),
        err.responseText || 'Import failed'
      );
    }
  });

  $results
    .on('click', '.wikidata-pagination a', function (event) {
      event.preventDefault();

      $.getJSON($(this).attr('href'), function (json) {
        $('body').scrollTo(0);
        renderResults(json);
      });
    })
    .on('click', '.wikidata-result button.select-record', function (event) {
      var qid = $(this).data('qid');
      if (selected_qids[qid]) {
        removeSelected(qid);
      } else {
        addSelected(qid, $(this).closest('.wikidata-result'));
      }
    });

  $selected.on('click', '.remove-selected', function (event) {
    event.stopPropagation();
    var qid = $(this).parent().data('qid');
    removeSelected(qid);
  });

  $(window).resize(resizeSelectedBox);
  resizeSelectedBox();
});
